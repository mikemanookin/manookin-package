classdef ObjectMotionTexture < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Texture leading duration (ms)
        tailTime = 250                  % Texture trailing duration (ms)
        waitTime = 2000                 % Time texture is presented before moving (ms)
        moveTime = 2000                 % Move duration (ms)
        contrast = 1.0                  % Texture contrast (0-1)
        textureStdev = 25               % Texture standard deviation (pixels)
        driftSpeed = 1000               % Texture drift speed (pix/sec)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        apertureRadius = 100            % Aperature radius between inner and outer gratings.     
        onlineAnalysis = 'extracellular' % Type of online analysis
        useRandomSeed = false            % Random or repeated seed?
        numberOfAverages = uint16(24)   % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stimulusClasses = {'center','surround','global','differential'}
        stimulusClass
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
            
            if ~obj.useRandomSeed
                % Generate the texture.
                obj.backgroundTexture = generateTexture(max(obj.canvasSize), obj.textureStdev, obj.contrast, 1);
                obj.centerTexture = generateTexture(max(obj.canvasSize), obj.textureStdev, obj.contrast, 1782);
                obj.backgroundTexture = uint8(obj.backgroundTexture*255);
                obj.centerTexture = uint8(obj.centerTexture*255);
            end
        end
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Generate the center texture.
            if ~strcmp(obj.stimulusClass,'surround')
                center = stage.builtin.stimuli.Image(obj.centerTexture);
                center.position = obj.canvasSize / 2;
                center.size = max(obj.canvasSize)*ones(1,2);
                
                % Set the minifying and magnifying functions to form discrete
                % stixels.
                center.setMinFunction(GL.NEAREST);
                center.setMagFunction(GL.NEAREST);

                % Add the stimulus to the presentation.
                p.addStimulus(center);

                if strcmp(obj.stimulusClass,'differential')
                    cenController = stage.builtin.controllers.PropertyController(center, 'position',...
                        @(state)orthogonalTrajectory(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
                else
                    cenController = stage.builtin.controllers.PropertyController(center, 'position',...
                        @(state)objectTrajectory(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
                end
                p.addController(cenController);
            end
            
            % Generate the background texture.
            if ~strcmp(obj.stimulusClass,'center')
                bground = stage.builtin.stimuli.Image(obj.backgroundTexture);
                bground.position = obj.canvasSize / 2;
                bground.size = min(obj.canvasSize)*ones(1,2);

                % Set the minifying and magnifying functions to form discrete
                % stixels.
                bground.setMinFunction(GL.NEAREST);
                bground.setMagFunction(GL.NEAREST);

                % Make the aperture
                [x,y] = meshgrid(linspace(-size(obj.backgroundTexture,1)/2,size(obj.backgroundTexture,1)/2,size(obj.backgroundTexture,1)), ...
                        linspace(-size(obj.backgroundTexture,2)/2,size(obj.backgroundTexture,2)/2,size(obj.backgroundTexture,2)));
                % Center the stimulus.
                distanceMatrix = sqrt(x.^2 + y.^2);
                circle = uint8((distanceMatrix >= obj.apertureRadius) * 255);
                mask = stage.core.Mask(circle);
                bground.setMask(mask);

                % Add the stimulus to the presentation.
                p.addStimulus(bground);
            end
            
            % Create the background grating. {'center','surround','global','differential'}
            % Make the grating visible only during the stimulus time.
            if ~strcmp(obj.stimulusClass,'surround')
                centerVisible = stage.builtin.controllers.PropertyController(center, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(centerVisible);
            end
            
            if ~strcmp(obj.stimulusClass,'center')
                backgroundVisible = stage.builtin.controllers.PropertyController(bground, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(backgroundVisible);

                bgController = stage.builtin.controllers.PropertyController(bground, 'position',...
                    @(state)objectTrajectory(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
                p.addController(bgController);
            end
            
            
            %--------------------------------------------------------------
            % Control the texture position.
            function p = objectTrajectory(obj, time)
                if time > 0
                    p = [obj.driftSpeed*time 0] + obj.canvasSize / 2;
                else
                    p = obj.canvasSize / 2;
                end
            end
            
            function p = orthogonalTrajectory(obj, time)
                if time > 0
                    p = [0 -obj.driftSpeed*time] + obj.canvasSize / 2;
                else
                    p = obj.canvasSize / 2;
                end
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
                obj.backgroundTexture = uint8(obj.backgroundTexture*255);
                obj.centerTexture = uint8(obj.centerTexture*255);
            end
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.waitTime + obj.moveTime;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end 