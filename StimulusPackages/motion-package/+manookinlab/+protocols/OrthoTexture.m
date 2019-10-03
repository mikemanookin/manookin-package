classdef OrthoTexture < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Texture leading duration (ms)
        tailTime = 250                  % Texture trailing duration (ms)
        waitTime = 2000                 % Time texture is presented before moving (ms)
        moveTime = 1000                 % Move duration (ms)
        contrast = 1.0                  % Texture contrast (0-1)
        textureStdevs = [15,30,45,60]   % Texture standard deviation (microns)
        moveSpeed = 600                 % Texture approach speed (um/sec)
        backgroundIntensity = 0.5       % Background light intensity (0-1)    
        onlineAnalysis = 'extracellular' % Type of online analysis
        useRandomSeed = true            % Random or repeated seed?
        numberOfAverages = uint16(400)  % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        textureStdevsType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        stimulusClasses = {'approaching','receding'}
        stimulusClass
        seed
        backgroundTexture
        centerTexture
        textureStdevPix
        driftSpeedPix
        maxTextureSize
        textureStdev
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
            
            
            obj.driftSpeedPix = obj.rig.getDevice('Stage').um2pix(obj.moveSpeed);
            
            if ~obj.useRandomSeed
                % Generate the texture.
                obj.backgroundTexture = generateTexture(round(max(obj.canvasSize)/5), obj.textureStdevPix/5, obj.contrast, 1);
                obj.backgroundTexture = uint8(obj.backgroundTexture*255);
            end
        end
        
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Generate the background texture.
            bground = stage.builtin.stimuli.Image(obj.backgroundTexture);
            bground.position = obj.canvasSize / 2;
            bground.size = max(obj.canvasSize)*ones(1,2);

            % Set the minifying and magnifying functions to form discrete
            % stixels.
            bground.setMinFunction(GL.NEAREST);
            bground.setMagFunction(GL.NEAREST);
            
            % Add the stimulus to the presentation.
            p.addStimulus(bground);
            
            % Make the grating visible only during the stimulus time.
            backgroundVisible = stage.builtin.controllers.PropertyController(bground, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(backgroundVisible);

            if strcmpi(obj.stimulusClass, 'approaching')
                bgController = stage.builtin.controllers.PropertyController(bground, 'size',...
                    @(state)approachTrajectory(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
            else
                % Compute the maximum texture size.
                obj.maxTextureSize = exp(log(max(obj.canvasSize)/200) + obj.driftSpeedPix/200*obj.moveTime*1e-3)*200;
                bgController = stage.builtin.controllers.PropertyController(bground, 'size',...
                    @(state)recedeTrajectory(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
            end
            p.addController(bgController);

            %--------------------------------------------------------------
            % Control the texture position.
            function p = approachTrajectory(obj, time)
                if time > 0 && time <= obj.moveTime*1e-3
%                     p = (obj.driftSpeedPix*time + max(obj.canvasSize))*ones(1,2);
                    p = exp(log(max(obj.canvasSize)/200) + obj.driftSpeedPix/200*time)*200*ones(1,2);
                else
                    p = max(obj.canvasSize)*ones(1,2);
                end
            end
            
            function p = recedeTrajectory(obj, time)
                if time > 0 && time <= obj.moveTime*1e-3
%                     p = (obj.driftSpeedPix*obj.moveTime*1e-3 + max(obj.canvasSize))*ones(1,2) - obj.driftSpeedPix*time*ones(1,2);
                    p = exp(log(obj.maxTextureSize/200) - obj.driftSpeedPix/200*time)*200*ones(1,2);
                else
%                     p = (obj.driftSpeedPix*obj.moveTime*1e-3 + max(obj.canvasSize))*ones(1,2);
                    p = obj.maxTextureSize*ones(1,2);
                end
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.stimulusClass = obj.stimulusClasses{mod(obj.numEpochsCompleted,length(obj.stimulusClasses))+1};
            epoch.addParameter('stimulusClass', obj.stimulusClass);
            
            obj.textureStdev = obj.textureStdevs(mod(floor(obj.numEpochsCompleted/length(obj.stimulusClasses)),length(obj.textureStdevs))+1);
            epoch.addParameter('textureStdev', obj.textureStdev);
            
            obj.textureStdevPix = obj.rig.getDevice('Stage').um2pix(obj.textureStdev);
            
            % Deal with the seed.
            if obj.useRandomSeed
                obj.seed = RandStream.shuffleSeed;
            else
                obj.seed = 1;
            end
            epoch.addParameter('seed', obj.seed);
            
            if obj.useRandomSeed
                % Generate the texture.
                obj.backgroundTexture = generateTexture(round(max(obj.canvasSize)/5), obj.textureStdevPix/5, obj.contrast, obj.seed);
                obj.backgroundTexture = uint8(obj.backgroundTexture*255);
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