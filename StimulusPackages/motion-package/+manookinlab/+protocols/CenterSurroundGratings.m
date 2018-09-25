classdef CenterSurroundGratings < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 2750                 % Stimulus duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        waitTime = 750                  % Stimulus wait time (ms)
        centerContrast = 0.5            % Center grating contrast (0-1)
        surroundContrasts = [0 0.5]     % Surround contrast (0-1)
        centerOrientation = 0           % Center orientation (deg)
        surroundOrientation = 0         % Surround orientation (deg)
        centerBarWidth = 50             % Center bar width (pix)
        surroundBarWidth = 100          % Surround bar width (pix)
        centerRadius = 150              % Center radius (pix)
        surroundRadius = 250            % Surround radius (pix)
        temporalFrequency = 4.0         % Grating temporal frequency (Hz)
        temporalClass = 'drifting'      % Grating temporal type.
        spatialClass = 'sinewave'       % Grating spatial type
        spatialPhase = 0.0              % Spatial phase (deg)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Online analysis type.
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        numberOfAverages = uint16(12)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'reversing', 'drifting'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        centerPhaseShift
        surroundPhaseShift
        surroundContrast
        sequence
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if length(obj.surroundContrasts) > 1
                colors = pmkmp(length(obj.surroundContrasts),'CubicYF');
            else
                colors = [0 0 0];
            end
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'surroundContrast'});
            
            % Get the correlation sequence.
            numReps = ceil(double(obj.numberOfAverages)/length(obj.surroundContrasts));
            obj.sequence = (1 : length(obj.surroundContrasts))' * ones(1, numReps);
            obj.sequence = obj.sequence(:)';
            % Just take the ones you need.
            obj.sequence = obj.sequence( 1 : obj.numberOfAverages );
        end
        
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create the surround grating.
            if obj.surroundContrast > 0                
                switch obj.spatialClass
                    case 'sinewave'
                        grate = stage.builtin.stimuli.Grating('sine');
                    otherwise % Square-wave grating
                        grate = stage.builtin.stimuli.Grating('square'); 
                end
                grate.orientation = obj.surroundOrientation;
                grate.size = max(obj.canvasSize)*ones(1,2);
                grate.position = obj.canvasSize/2 + obj.centerOffset;
                grate.spatialFreq = 1/(2*obj.surroundBarWidth); %convert from bar width to spatial freq
                grate.contrast = obj.surroundContrast;
                grate.color = 2*obj.backgroundIntensity;
                %calc to apply phase shift s.t. a contrast-reversing boundary
                %is in the center regardless of spatial frequency. Arbitrarily
                %say boundary should be positve to right and negative to left
                %crosses x axis from neg to pos every period from 0
                zeroCrossings = 0:(grate.spatialFreq^-1):grate.size(1); 
                offsets = zeroCrossings-grate.size(1)/2; %difference between each zero crossing and center of texture, pixels
                [shiftPix, ~] = min(offsets); % min(offsets(offsets>0)); %positive shift in pixels
                phaseShift_rad = (shiftPix/(grate.spatialFreq^-1))*(2*pi); %phaseshift in radians
                obj.surroundPhaseShift = 360*(phaseShift_rad)/(2*pi) + obj.spatialPhase; %phaseshift in degrees
                grate.phase = obj.surroundPhaseShift ; %keep contrast reversing boundary in center

                % Add the grating.
                p.addStimulus(grate);

                % Make the grating visible only during the stimulus time.
                grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(grateVisible);

                %--------------------------------------------------------------
                % Control the grating phase.
                if strcmp(obj.temporalClass, 'drifting')
                    grateController = stage.builtin.controllers.PropertyController(grate, 'phase',...
                        @(state)setDriftingGrating(obj, state.time - obj.preTime * 1e-3, obj.surroundPhaseShift));
                else
                    grateController = stage.builtin.controllers.PropertyController(grate, 'phase',...
                        @(state)setReversingGrating(obj, state.time - obj.preTime * 1e-3, obj.surroundPhaseShift));
                end
                p.addController(grateController);
                
                % Create the aperture.
                if obj.surroundRadius > 0 && obj.surroundRadius < max(obj.canvasSize/2)
                    bg = stage.builtin.stimuli.Ellipse();
                    bg.color = obj.backgroundIntensity;
                    bg.radiusX = obj.surroundRadius;
                    bg.radiusY = obj.surroundRadius;
                    bg.position = obj.canvasSize/2 + obj.centerOffset;
                    p.addStimulus(bg);
                end
            end
            
            % Create the center grating.
            switch obj.spatialClass
                case 'sinewave'
                    grate1 = stage.builtin.stimuli.Grating('sine');
                otherwise % Square-wave grating
                    grate1 = stage.builtin.stimuli.Grating('square'); 
            end
            grate1.orientation = obj.centerOrientation;
            grate1.size = obj.centerRadius*2*ones(1,2);
            grate1.position = obj.canvasSize/2 + obj.centerOffset;
            grate1.spatialFreq = 1/(2*obj.centerBarWidth); %convert from bar width to spatial freq
            grate1.contrast = obj.centerContrast;
            grate1.color = 2*obj.backgroundIntensity;
            zeroCrossings = 0:(grate1.spatialFreq^-1):grate1.size(1); 
            offsets = zeroCrossings-grate1.size(1)/2; %difference between each zero crossing and center of texture, pixels
            [shiftPix, ~] = min(offsets); % min(offsets(offsets>0)); %positive shift in pixels
            phaseShift_rad = (shiftPix/(grate1.spatialFreq^-1))*(2*pi); %phaseshift in radians
            obj.centerPhaseShift = 360*(phaseShift_rad)/(2*pi) + obj.spatialPhase; %phaseshift in degrees
            grate1.phase = obj.centerPhaseShift; %keep contrast reversing boundary in center
            
            % Make it circular.
            [x,y] = meshgrid(linspace(-obj.centerRadius,obj.centerRadius,obj.centerRadius*2));
            distanceMatrix = sqrt(x.^2 + y.^2);
            circle = uint8((distanceMatrix < obj.centerRadius) * 255);
            mask = stage.core.Mask(circle);
            grate1.setMask(mask);

            % Add the grating.
            p.addStimulus(grate1);

            % Make the grating visible only during the stimulus time.
            grate1Visible = stage.builtin.controllers.PropertyController(grate1, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(grate1Visible);
            
            %--------------------------------------------------------------
            % Control the grating phase.
            if strcmp(obj.temporalClass, 'drifting')
                grate1Controller = stage.builtin.controllers.PropertyController(grate1, 'phase',...
                    @(state)setDriftingGrating(obj, state.time - (obj.preTime+obj.waitTime) * 1e-3, obj.centerPhaseShift));
            else
                grate1Controller = stage.builtin.controllers.PropertyController(grate1, 'phase',...
                    @(state)setReversingGrating(obj, state.time - (obj.preTime+obj.waitTime) * 1e-3, obj.centerPhaseShift));
            end
            p.addController(grate1Controller);
            
            % Set the drifting grating.
            function phase = setDriftingGrating(obj, time, phaseShift)
                if time >= 0
                    phase = obj.temporalFrequency * time * 2 * pi;
                else
                    phase = 0;
                end

                phase = phase*180/pi + phaseShift;
            end

            % Set the reversing grating
            function phase = setReversingGrating(obj, time, phaseShift)
                if time >= 0
                    phase = round(0.5 * sin(time * 2 * pi * obj.temporalFrequency) + 0.5) * pi;
                else
                    phase = 0;
                end

                phase = phase*180/pi + phaseShift;
            end
        end
        
        
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current sequence name.
            obj.surroundContrast = obj.surroundContrasts(obj.sequence( obj.numEpochsCompleted+1 ));

            % Save the surround contrast
            epoch.addParameter('surroundContrast', obj.surroundContrast);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end