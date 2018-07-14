classdef ObjectMotionTexture < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Grating leading duration (ms)
        stimTime = 6000                 % Grating duration (ms)
        tailTime = 500                  % Grating trailing duration (ms)
        contrast = 1.0                  % Grating contrast (0-1)
        orientation = 0.0               % Grating orientation (deg)
        textureStdev = 25               % Texture standard deviation (pixels)
        jitterSpeed = 1000              % Grating jitter/frame (pix/sec)
        driftSpeed = 1000               % Center drift speed (pix/sec)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        innerRadius = 100               % Center radius in pixels.
        apertureRadius = 150            % Aperature radius between inner and outer gratings.     
        onlineAnalysis = 'extracellular' % Type of online analysis
        useRandomSeed = false            % Random or repeated seed?
        numberOfAverages = uint16(24)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stimulusClasses = {'eye+object','eye','object','eye+object drift'}
        stimulusClass
        driftStep
        seed
        backgroundTexture
        centerTexture
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            if ~strcmp(obj.onlineAnalysis, 'none')
                colors = [0 0 0; 0.8 0 0; 0 0.7 0.2; 0 0.2 1];
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',colors,...
                    'groupBy',{'stimulusClass'});
            end
            obj.driftStep = obj.driftSpeed / obj.frameRate;
            
            if ~obj.useRandomSeed
                % Generate the texture.
                obj.backgroundTexture = generateTexture(max(obj.canvasSize), obj.textureStdev, obj.contrast, 1);
                obj.centerTexture = generateTexture(max(obj.canvasSize), obj.textureStdev, obj.contrast, 1782);
            end
        end
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Generate the center texture.
            
            
            % Generate the background texture.
            
            % Create the background grating.
            if ~strcmp(obj.stimulusClass, 'object')
                switch obj.spatialClass
                    case 'sinewave'
                        bGrating = stage.builtin.stimuli.Grating('sine');
                    otherwise % Square-wave grating
                        bGrating = stage.builtin.stimuli.Grating('square'); 
                end
                bGrating.orientation = obj.orientation;
                bGrating.size = max(obj.canvasSize) * ones(1,2);
                bGrating.position = obj.canvasSize/2 + obj.centerOffset;
                bGrating.spatialFreq = 1/(2*obj.barWidth); %convert from bar width to spatial freq
                bGrating.contrast = obj.contrast;
                bGrating.color = 2*obj.backgroundIntensity;
            end
            
            if ~strcmp(obj.stimulusClass, 'object')
                bGrating.phase = obj.phaseShift + obj.spatialPhase; 
                p.addStimulus(bGrating);
                
                % Make the grating visible only during the stimulus time.
                grate2Visible = stage.builtin.controllers.PropertyController(bGrating, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(grate2Visible);
                
                bgController = stage.builtin.controllers.PropertyController(bGrating, 'phase',...
                    @(state)surroundTrajectory(obj, state.time - obj.preTime * 1e-3));
                p.addController(bgController);
            end
            
            if obj.apertureRadius > obj.innerRadius
                mask = stage.builtin.stimuli.Ellipse();
                mask.color = obj.backgroundIntensity;
                mask.radiusX = obj.apertureRadius;
                mask.radiusY = obj.apertureRadius;
                mask.position = obj.canvasSize / 2 + obj.centerOffset;
                p.addStimulus(mask);
            end
            
            % Add the grating.
            p.addStimulus(grate);
            
            % Make the grating visible only during the stimulus time.
            grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(grateVisible);
            
            %--------------------------------------------------------------
            % Control the grating phase.
            
            %{'eye+object','eye','object','eye+object drift'}
            switch obj.stimulusClass
                case 'eye+object drift'
                    imgController = stage.builtin.controllers.PropertyController(grate, 'phase',...
                        @(state)objectDriftTrajectory(obj, state.time - obj.preTime * 1e-3));
                otherwise
                    imgController = stage.builtin.controllers.PropertyController(grate, 'phase',...
                        @(state)objectTrajectory(obj, state.time - obj.preTime * 1e-3));
            end
            p.addController(imgController);
            
            % Object/center trajectory.
            function p = objectTrajectory(obj, time)
                if time > 0
                    p = obj.noiseStream.randn*2*pi * obj.stepSize / obj.barWidth;
                else
                    p = 0;
                end
                obj.centerPhase = obj.centerPhase + p;
                p = obj.centerPhase*180/pi + obj.phaseShift + obj.spatialPhase;
            end
            
            % Set the drifting grating.
            function phase = objectDriftTrajectory(obj, time)
                if time >= 0
                    phase = (obj.driftStep/obj.barWidth * 2 * pi)+(obj.noiseStream.randn*2*pi * obj.stepSize / obj.barWidth);
                else
                    phase = 0;
                end
                obj.centerPhase = obj.centerPhase + phase;
                phase = obj.centerPhase*180/pi + obj.phaseShift + obj.spatialPhase;
            end
            
            % Surround trajectory
            function p = surroundTrajectory(obj, time)
                if time > 0
                    p = obj.noiseStream2.randn*2*pi * obj.stepSize / obj.barWidth;
                else
                    p = 0;
                end
                obj.surroundPhase = obj.surroundPhase + p;
                p = obj.surroundPhase*180/pi + obj.phaseShift + obj.spatialPhase;
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.stimulusClass = obj.stimulusClasses{mod(obj.numEpochsCompleted,length(obj.stimulusClasses))+1};
            epoch.addParameter('stimulusClass', obj.stimulusClass);
            
            % Deal with the seed.
            if obj.useRandomSeed
                obj.seed = RandStream.shuffleSeed;
            else
                obj.seed = 1;
            end
            if strcmp(obj.stimulusClass,'eye+object')
                seed2 = obj.seed + 1781;
            else
                seed2 = obj.seed;
            end
            epoch.addParameter('surroundSeed', seed2);
            
            if obj.useRandomSeed
                % Generate the texture.
                obj.backgroundTexture = generateTexture(max(obj.canvasSize), obj.textureStdev, obj.contrast, 1);
                obj.centerTexture = generateTexture(max(obj.canvasSize), obj.textureStdev, obj.contrast, 1782);
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