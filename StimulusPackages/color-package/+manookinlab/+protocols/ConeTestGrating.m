classdef ConeTestGrating < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Grating leading duration (ms)
        stimTime = 4000                 % Grating duration (ms)
        tailTime = 250                  % Grating trailing duration (ms)
        contrast = 1.0                  % Grating contrast (0-1)
        spatialFrequency = 18.0;        % Spatial frequency (cyc/short axis of screen)
        temporalFrequency = 2.0         % Temporal frequency (Hz)
        spatialPhase = 0.0              % Spatial phase of grating (deg)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        onlineAnalysis = 'extracellular'% Type of online analysis
        numberOfAverages = uint16(24)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        rawImage
        chromaticClasses = {'achromatic','M-iso','L-iso','S-iso'};
        chromaticClass
        orientations = 0:30:150 % Orientations to test
        orientation % Current orientation.
        backgroundMean = [0.5 0.5 0.5] % Achromatic LMS: [1, 0.877, 0.329] for nemestrina
        cycleFrames
        myGrating
        spatialPhaseRad
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            % Calculate the spatial phase in radians.
            obj.spatialPhaseRad = obj.spatialPhase / 180 * pi;
            
            % Calculate the number of cycle frames.
            obj.cycleFrames  = floor(obj.frameRate / obj.temporalFrequency);
        end
        
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundMean); % Set background intensity
            
            % Create the grating.
            grate = stage.builtin.stimuli.Image(squeeze(obj.myGrating(1,:,:,:)));
            grate.position = obj.canvasSize / 2;
            grate.size = ceil(sqrt(obj.canvasSize(1)^2 + obj.canvasSize(2)^2))*ones(1,2);
            grate.orientation = obj.orientation;
            
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
                @(state)setDriftingGrating(obj, state.time - obj.preTime * 1e-3));
            p.addController(imgController);
            
            % Set the drifting grating.
            function g = setDriftingGrating(obj, time)
                frame = round(time * 60);
                
                k = mod(frame, obj.cycleFrames) + 1;
                
                g = squeeze(obj.myGrating(k,:,:,:));
            end
        end
        
        function setRawImage(obj)
            downsamp = 3;
            sz = ceil(sqrt(obj.canvasSize(1)^2 + obj.canvasSize(2)^2));
            [x,y] = meshgrid(...
                linspace(-sz/2, sz/2, sz/downsamp), ...
                linspace(-sz/2, sz/2, sz/downsamp));
            
            % Calculate the orientation in radians.
            rotRads = obj.orientation / 180 * pi;
            
            % Center the stimulus.
            x = x + obj.centerOffset(1)*cos(rotRads);
            y = y + obj.centerOffset(2)*sin(rotRads);
            
            x = x / min(obj.canvasSize) * 2 * pi;
            y = y / min(obj.canvasSize) * 2 * pi;
            
            % Calculate the raw grating image.
            img = (cos(0)*x + sin(0) * y) * obj.spatialFrequency;
            obj.rawImage = img(1:2,:);
            obj.rawImage = repmat(obj.rawImage, [1 1 3]);
        end
        
        function makeMyGrating(obj)
            obj.myGrating = zeros(obj.cycleFrames, size(obj.rawImage,1), size(obj.rawImage,2), 3);
            for k = 1 : obj.cycleFrames
                phase = k / obj.cycleFrames * 2 * pi;

                g = cos(obj.spatialPhaseRad + phase + obj.rawImage);
                
                g = obj.contrast * g;
                
                for m = 1 : 3
                    g(:,:,m) = obj.backgroundMean(m)*(obj.colorWeights(m) * g(:,:,m)) + obj.backgroundMean(m);
                end
                obj.myGrating(k,:,:,:) = g;
            end
            % Make it uint8
            obj.myGrating = uint8(obj.myGrating * 255);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.chromaticClass = obj.chromaticClasses{...
                mod(obj.numEpochsCompleted, length(obj.chromaticClasses))+1};
            obj.orientation = obj.orientations(...
                mod(floor(obj.numEpochsCompleted/length(obj.chromaticClasses)), length(obj.orientations))+1);
            
            % Set the LED weights.
            obj.setColorWeights();
            
            % Set the gun contrast for the white point for achromatic stimuli.
            if strcmp(obj.chromaticClass, 'achromatic')
                obj.colorWeights = [1 1 0];
            end
            
            % Set up the raw image.
            obj.setRawImage();
            
            % Make the grating.
            obj.makeMyGrating();

            % Add parameters you'll need for analysis.
            epoch.addParameter('chromaticClass', obj.chromaticClass);
            epoch.addParameter('orientation', obj.orientation);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end