classdef CircularGrating < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Spot leading duration (ms)
        stimTime = 3000                 % Spot duration (ms)
        tailTime = 1000                 % Spot trailing duration (ms)
        waitTime = 1000                 % Grating wait duration (ms)
        contrast = 1.0                  % Grating contrast (0-1)
        temporalFrequency = 4.0         % Modulation frequency (Hz)
        spatialFrequency = 4.6          % Spatial frequency
        spatialClass = 'sinewave'       % Spatial type (sinewave or squarewave)
        direction = 'outward'           % Outward or inward?
        innerRadius = 50                % Inner radius (pix)
        outerRadius = 150               % Outer radius (pix)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        onlineAnalysis = 'none'         % Online analysis type.
        numberOfAverages = uint16(3)    % Number of epochs
    end
    
    properties (Hidden)
        ampType
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        directionType = symphonyui.core.PropertyType('char', 'row', {'outward', 'inward'})
        frameValues
        cycleFrames
        preStimFrames
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('symphonyui.builtin.figures.MeanResponseFigure', obj.rig.getDevice(obj.amp));
            
            obj.getFrameValues();
            
            obj.preStimFrames = floor((obj.preTime + obj.waitTime) / 1000 * obj.frameRate);
        end
        
        function getFrameValues(obj)
            downsamp = 3;
            [x,y] = meshgrid(...
                linspace(-obj.canvasSize(1)/2, obj.canvasSize(1)/2, obj.canvasSize(1)/downsamp), ...
                linspace(-obj.canvasSize(2)/2, obj.canvasSize(2)/2, obj.canvasSize(2)/downsamp));
            
            % Center the stimulus.
            x = x + obj.centerOffset(1);
            y = y + obj.centerOffset(2);
            
            % Get the radial calculation.
            r = sqrt(x.^2 + y.^2);
            
            r2 = r / min(obj.canvasSize/2) * 2 * pi;
            
            % Calculate the cycle frames.
            obj.cycleFrames = obj.frameRate / obj.temporalFrequency;
            
            if strcmp(obj.direction, 'outward')
                d = -1;
            else
                d = 1;
            end
            
            % Create an image filter.
            f = ones(size(r));
            if obj.innerRadius > 0
                pts = r < obj.innerRadius;
                v = 1-exp(-(r(pts).^2/(obj.innerRadius^2)));
                v = v - min(v(:));
                v = v / max(v(:));
%                 f(pts) = v;
                f(pts) = 0;
            end
            
            pts = r > obj.outerRadius;
            if sum(pts(:)) > 0
                v = exp(-(r(pts).^2/((obj.outerRadius)^2)));
                v = v - min(v(:));
                v = v / max(v(:));
%                 f(pts) = v;
                f(pts) = 0;
            end
            
            obj.frameValues = zeros(size(r,1), size(r,2), round(obj.cycleFrames));
            
            inc = 1 / obj.cycleFrames * 2 * pi;
            for k = 1 : round(obj.cycleFrames)
                phase = d * k * inc;
                
                img = sin(phase + r2 * obj.spatialFrequency);
                
                % Smooth the transitions with a filter.
                img = img .* f;
                
                if strcmp(obj.spatialClass, 'sinewave')
                    obj.frameValues(:,:,k) = img;
                else
                    obj.frameValues(:,:,k) = sign(img);
                end
            end
            
            obj.cycleFrames = round(obj.cycleFrames);
            
            % Multiply by contrast
            obj.frameValues = 0.5 * obj.contrast * obj.frameValues + 0.5;
            
            % Convert to 8 bit.
            obj.frameValues = uint8(255*obj.frameValues);
        end
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Create the grating.
            grate = stage.builtin.stimuli.Image(obj.frameValues(:,:,1));
            grate.position = obj.canvasSize / 2;
            grate.size = obj.canvasSize;
            
            % Set the minifying and magnifying functions.
            grate.setMinFunction(GL.NEAREST);
            grate.setMagFunction(GL.NEAREST);
            
            % Add the grating.
            p.addStimulus(grate);
            
            % Make the grating visible only during the stimulus time.
            grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(grateVisible);
            
            %--------------------------------------------------------------
            % Generate the grating.
            imgController = stage.builtin.controllers.PropertyController(grate, 'imageMatrix',...
                @(state)setDriftingGrating(obj, state.frame - obj.preStimFrames));
            p.addController(imgController);
            
            % Set the drifting grating.
            function g = setDriftingGrating(obj, frame)
                if frame >= 0
                    g = obj.frameValues(:,:,mod(frame, obj.cycleFrames)+1);
                else
                    g = obj.frameValues(:,:,1);
                end
            end
        end
        
        % Same presentation each epoch in a run. Replay.
        function controllerDidStartHardware(obj)
            controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            if (obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < obj.numberOfAverages)
                obj.rig.getDevice('Stage').replay
            else
                obj.rig.getDevice('Stage').play(obj.createPresentation());
            end
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end