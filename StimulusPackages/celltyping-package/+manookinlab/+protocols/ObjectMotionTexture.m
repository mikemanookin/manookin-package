classdef ObjectMotionTexture < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Texture leading duration (ms)
        tailTime = 250                  % Texture trailing duration (ms)
        waitTime = 2000                 % Time texture is presented before moving (ms)
        moveTime = 2000                 % Move duration (ms)
        contrast = 1.0                  % Texture contrast (0-1)
        textureStdev = 15               % Texture standard deviation (microns)
        driftSpeed = 1000               % Texture drift speed (um/sec)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        radius = 200                    % Center radius (microns)
        apertureRadius = 250            % Aperature radius between inner and outer textures (microns).     
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
        textureStdevPix
        driftSpeedPix
        radiusPix
        apertureRadiusPix
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
            
            obj.textureStdevPix = obj.rig.getDevice('Stage').um2pix(obj.textureStdev);
            obj.driftSpeedPix = obj.rig.getDevice('Stage').um2pix(obj.driftSpeed);
            obj.radiusPix = obj.rig.getDevice('Stage').um2pix(obj.radius);
            obj.apertureRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.apertureRadius);
            
            if ~obj.useRandomSeed
                % Generate the texture.
                obj.backgroundTexture = generateTexture(round((max(obj.canvasSize)+round(obj.moveTime*1e-3*obj.driftSpeedPix*2))/5), obj.textureStdevPix/5, obj.contrast, 1);
                obj.backgroundTexture = uint8(obj.backgroundTexture*255);
                obj.getCenterTexture();
            end
        end
        
        function getCenterTexture(obj)
            numFrames = ceil(obj.moveTime * 1e-3 * obj.frameRate) + 15;
            
            obj.centerTexture = uint8(zeros(round(obj.radiusPix*2/5),round(obj.radiusPix*2/5),numFrames));
            center = round(size(obj.backgroundTexture,1)/2);
            shiftPerFrame = obj.driftSpeedPix/5 / obj.frameRate;
            xpos = center-round(center/2) + (1 : round(obj.radiusPix*2/5));
            for k = 1 : numFrames
                ypos = round((k-1)*shiftPerFrame) + center-round(center/2) + (1 : round(obj.radiusPix*2/5));
                obj.centerTexture(:,:,k) = obj.backgroundTexture(ypos,xpos);
            end
        end
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Generate the background texture.
            bground = stage.builtin.stimuli.Image(obj.backgroundTexture);
            bground.position = obj.canvasSize / 2;
            bground.size = max(obj.canvasSize)*ones(1,2)+round(obj.moveTime*1e-3*obj.driftSpeedPix*2);

            % Set the minifying and magnifying functions to form discrete
            % stixels.
            bground.setMinFunction(GL.NEAREST);
            bground.setMagFunction(GL.NEAREST);
            
            % Add the stimulus to the presentation.
            p.addStimulus(bground);

            % Make the aperture{'center','surround','global','differential'}
            if strcmp(obj.stimulusClass,'center')
                % Size is 0 to 1
                sz = (obj.radiusPix*2)/min(obj.canvasSize);
                % Create the outer mask.
                if sz < 1
                    aperture = stage.builtin.stimuli.Rectangle();
                    aperture.position = obj.canvasSize/2;
                    aperture.color = obj.backgroundIntensity;
                    aperture.size = obj.canvasSize;
                    [x,y] = meshgrid(linspace(-obj.canvasSize(1)/2,obj.canvasSize(1)/2,obj.canvasSize(1)), ...
                        linspace(-obj.canvasSize(2)/2,obj.canvasSize(2)/2,obj.canvasSize(2)));
                    distanceMatrix = sqrt(x.^2 + y.^2);
                    circle = uint8((distanceMatrix >= obj.radiusPix) * 255);
                    mask = stage.core.Mask(circle);
                    aperture.setMask(mask);
                    p.addStimulus(aperture); %add aperture
                end
            elseif strcmp(obj.stimulusClass,'surround') || (strcmp(obj.stimulusClass,'differential') && obj.radiusPix < obj.apertureRadiusPix)
                bg = stage.builtin.stimuli.Ellipse();
                bg.color = obj.backgroundIntensity;
                bg.radiusX = obj.apertureRadiusPix;
                bg.radiusY = obj.apertureRadiusPix;
                bg.position = obj.canvasSize/2;
                p.addStimulus(bg);
            elseif strcmp(obj.stimulusClass,'global')  && obj.radiusPix < obj.apertureRadiusPix
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = obj.canvasSize/2;
                aperture.color = obj.backgroundIntensity;
                aperture.size = obj.canvasSize;
                [x,y] = meshgrid(linspace(-obj.canvasSize(1)/2,obj.canvasSize(1)/2,obj.canvasSize(1)), ...
                    linspace(-obj.canvasSize(2)/2,obj.canvasSize(2)/2,obj.canvasSize(2)));
                distanceMatrix = sqrt(x.^2 + y.^2);
                circle = uint8((distanceMatrix <= obj.apertureRadiusPix & distanceMatrix > obj.radiusPix) * 255);
                mask = stage.core.Mask(circle);
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
            
            % Create the background grating. {'center','surround','global','differential'}
            % Make the grating visible only during the stimulus time.
            backgroundVisible = stage.builtin.controllers.PropertyController(bground, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(backgroundVisible);

            bgController = stage.builtin.controllers.PropertyController(bground, 'position',...
                @(state)objectTrajectory(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
            p.addController(bgController);
            
            % Generate the center texture.
            if strcmp(obj.stimulusClass,'differential')
                center = stage.builtin.stimuli.Image(obj.centerTexture(:,:,1));
                center.position = obj.canvasSize / 2;
                center.size = obj.radiusPix*2*ones(1,2);
                
                % Set the minifying and magnifying functions to form discrete
                % stixels.
                center.setMinFunction(GL.NEAREST);
                center.setMagFunction(GL.NEAREST);
                
                [x,y] = meshgrid(linspace(-size(obj.centerTexture,1)/2,size(obj.centerTexture,1)/2,size(obj.centerTexture,1)), ...
                    linspace(-size(obj.centerTexture,2)/2,size(obj.centerTexture,2)/2,size(obj.centerTexture,2)));
                % Center the stimulus.
                distanceMatrix = sqrt(x.^2 + y.^2);
                circle = uint8((distanceMatrix <= obj.radiusPix/5) * 255);
                mask = stage.core.Mask(circle);
                center.setMask(mask);

                % Add the stimulus to the presentation.
                p.addStimulus(center);
                
                cenController = stage.builtin.controllers.PropertyController(center, 'imageMatrix',...
                    @(state)orthogonalTrajectory(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
                p.addController(cenController);
                
                centerVisible = stage.builtin.controllers.PropertyController(center, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(centerVisible);
            end
             
            %--------------------------------------------------------------
            % Control the texture position.
            function p = objectTrajectory(obj, time)
                if time > 0 && time <= obj.moveTime*1e-3
                    p = [obj.driftSpeedPix*time 0] + obj.canvasSize / 2;
                else
                    p = obj.canvasSize / 2;
                end
            end
            
            function p = orthogonalTrajectory(obj, time)
                if time > 0 && time <= obj.moveTime*1e-3
                    fr = floor(time * obj.frameRate) + 1;
                    p = obj.centerTexture(:,:,fr);
                else
                    p = obj.centerTexture(:,:,1);
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
            epoch.addParameter('seed', obj.seed);
            
            if obj.useRandomSeed
                % Generate the texture.
                obj.backgroundTexture = generateTexture(round((max(obj.canvasSize)+round(obj.moveTime*1e-3*obj.driftSpeedPix*2))/5), obj.textureStdevPix/5, obj.contrast, obj.seed);
                obj.backgroundTexture = uint8(obj.backgroundTexture*255);
                obj.getCenterTexture();
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