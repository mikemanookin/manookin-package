classdef SaccadeAndPursuitCRF < edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 750                  % Stimulus duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        waitTime = 500                  % Stimulus wait duration (ms)
        flashTime = 250                 % Spot flash time (ms)
        delayTimes = [0,100,200,300,400,500] % Delay time (ms)
        spotRadius = 50                % Spot radius (pix).
        contrasts = [0 0.0625 0.0625 0.125 0.25 0.375 0.5 0.75 1] % Spot contrasts (-1:1)
        speed = 2750                    % Background motion speed (pix/sec)
        stimulusIndex = 2               % Stimulus number (1:161)
        surroundContrast = 0.5          % Surround contrast (0-1)
        surroundBarWidth = 100          % Surround bar width (pix)
        maskDiameter = 50                % Mask diameter in pixels
        apertureDiameter = 2000         % Aperture diameter in pixels.
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        randomSeed = false              % Use a random (true) or repeating seed (false)
        centerClass = 'spot'            % Center stimulus class
        surroundClass = 'natural image' % Background stimulus type.
        chromaticClass = 'achromatic'   % Spot color
        onlineAnalysis = 'extracellular'         % Type of online analysis
        numberOfAverages = uint16(108)    % Number of epochs
    end
    
    properties (Hidden)
        ampType
        centerClassType = symphonyui.core.PropertyType('char', 'row', {'spot','high freq grating', 'low freq grating'})
        surroundClassType = symphonyui.core.PropertyType('char', 'row', {'natural image','plaid','grating'})
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','red-green isoluminant','red-green isochromatic'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        imageMatrix
        backgroundIntensity
        backgroundMeans
        imageName
        subjectName
        magnificationFactor =  4
        currentStimSet
        backgroundTypes
        backgroundType
        seed
        noiseStream
        contrast
        orientationRads
        delayTime
        rgbMeans
        rgbValues
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('edu.washington.riekelab.manookin.figures.ResponseFigure', obj.rig.getDevices(obj.amp), ...
                'numberOfAverages', obj.numberOfAverages);
            
            if length(unique(obj.delayTimes)) > 1
                obj.backgroundTypes = {'stationary','fixation'};
            else
                obj.backgroundTypes = {'stationary','pursuit','fixation'};
            end
            
            obj.showFigure('edu.washington.riekelab.manookin.figures.ContrastResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'preTime',obj.preTime+obj.waitTime+obj.delayTimes(1),...
                'stimTime',obj.flashTime,...
                'contrasts',unique(obj.contrasts),...
                'groupBy','backgroundType',...
                'groupByValues',obj.backgroundTypes,...
                'temporalClass','pulse');
            
            obj.muPerPixel = 0.8;
            
            % Get the image and subject names.
            switch obj.surroundClass
                case 'natural image'
                    obj.getImageSubject();
                case 'plaid'
                    obj.getPlaid();
                case 'grating'
                    obj.getGrating();
            end
            
            if strcmp(obj.stageClass,'LightCrafter')
                obj.chromaticClass = 'achromatic';
            end
            
            % Check the color space.
            if strcmp(obj.chromaticClass,'achromatic')
                obj.rgbMeans = 0.5;
                obj.rgbValues = 1;
                obj.backgroundMeans = obj.backgroundIntensity*ones(1,3);
            else
                [obj.rgbMeans, ~, deltaRGB] = getMaxContrast(obj.quantalCatch, obj.chromaticClass);
                obj.rgbValues = deltaRGB*obj.backgroundIntensity + obj.backgroundIntensity;
                obj.imageMatrix = repmat(double(obj.imageMatrix), [1 1 3]);
                for k = 1 : 2
                    obj.imageMatrix(:,:,k) = obj.imageMatrix(:,:,k)*obj.rgbMeans(k)*2;
                end
                obj.imageMatrix(:,:,3) = 0;
                obj.imageMatrix = uint8(obj.imageMatrix);
                obj.backgroundMeans = obj.rgbMeans(:)';
            end
        end
        
        function getPlaid(obj)
            obj.backgroundIntensity = 0.5;
            
            [x,y] = meshgrid(...
                linspace(-1536/2, 1536/2, 1536), ...
                linspace(-1024/2, 1024/2, 1024));
            
            % Center the stimulus.
            x = x + obj.centerOffset(1);
            y = y + obj.centerOffset(2);
            
            x = x / (obj.surroundBarWidth*2/obj.magnificationFactor) * 2 * pi;
            y = y / (obj.surroundBarWidth*2/obj.magnificationFactor) * 2 * pi;
            
            % Calculate the raw plaid image.
            img = obj.surroundContrast*sign(cos((cos(pi)*x + sin(pi) * y)) + cos((cos(pi/2)*x + sin(pi/2) * y)));
            
            img = 0.5*img + 0.5;
            
            img = img*255; %rescale s.t. brightest point is maximum monitor level
            obj.imageMatrix = uint8(img);
        end
        
        function getGrating(obj)
            obj.backgroundIntensity = 0.5;
            
            [x,y] = meshgrid(...
                linspace(-1536/2, 1536/2, 1536), ...
                linspace(-1024/2, 1024/2, 1024));
            
            % Center the stimulus.
            x = x + obj.centerOffset(1);
            y = y + obj.centerOffset(2);
            
            x = x / (obj.surroundBarWidth*2/obj.magnificationFactor) * 2 * pi;
            y = y / (obj.surroundBarWidth*2/obj.magnificationFactor) * 2 * pi;
            
            % Calculate the raw grating image.
            img = obj.surroundContrast*sign(cos(x));
            
            img = 0.5*img + 0.5;
            
            img = img*255; %rescale s.t. brightest point is maximum monitor level
            obj.imageMatrix = uint8(img);
        end
        
        function getImageSubject(obj)
            % Get the resources directory.
            tmp = strsplit(pwd,'\');
            pkgDir = [tmp{1},'\',tmp{2},'\',tmp{3},'\',tmp{4},'\GitRepos\Symphony2\manookin-package\'];
            
            obj.currentStimSet = 'dovesFEMstims20160826.mat';
            
            % Load the current stimulus set.
            im = load([pkgDir,'\resources\',obj.currentStimSet]);
            
            % Get the image name.
            obj.imageName = im.FEMdata(obj.stimulusIndex).ImageName;
            
            % Load the image.
            fileId = fopen([pkgDir,'resources\doves\images\', obj.imageName],'rb','ieee-be');
            img = fread(fileId, [1536 1024], 'uint16');
            fclose(fileId);
            
            img = double(img');
            img = (img./max(img(:))); %rescale s.t. brightest point is maximum monitor level
            obj.backgroundIntensity = mean(img(:));%set the mean to the mean over the image
            img = img.*255; %rescale s.t. brightest point is maximum monitor level
            obj.imageMatrix = uint8(img);
            
            % Load the fixations for the image.
            f = load([pkgDir,'resources\doves\fixations\', obj.imageName, '.mat']);
            obj.subjectName = f.subj_names_list{im.FEMdata(obj.stimulusIndex).SubjectIndex};
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundMeans);
            
            % Create your scene.
            scene = stage.builtin.stimuli.Image(obj.imageMatrix);
            scene.size = [size(obj.imageMatrix,2) size(obj.imageMatrix,1)]*obj.magnificationFactor;
            p0 = obj.canvasSize/2 + obj.centerOffset;
            scene.position = p0;

            scene.setMinFunction(GL.NEAREST);
            scene.setMagFunction(GL.NEAREST);

            % Add the stimulus to the presentation.
            p.addStimulus(scene);

            %apply eye trajectories to move image around
            if strcmp(obj.backgroundType, 'pursuit')
                scenePosition = stage.builtin.controllers.PropertyController(scene,...
                    'position', @(state)getScenePosition(obj, state.time - obj.preTime*1e-3, p0));
                % Add the controller.
                p.addController(scenePosition);
            elseif strcmp(obj.backgroundType,'fixation')
                scenePosition = stage.builtin.controllers.PropertyController(scene,...
                    'position', @(state)getScenePositionFix(obj, state.time - obj.preTime*1e-3, p0));
                % Add the controller.
                p.addController(scenePosition);
            end

            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time > obj.preTime * 1e-3 && state.time <= (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);

            %--------------------------------------------------------------
            % Size is 0 to 1
            sz = (obj.apertureDiameter)/min(obj.canvasSize);
            % Create the outer mask.
            if sz < 1
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = obj.canvasSize/2;
                aperture.color = obj.backgroundMeans;
                aperture.size = obj.canvasSize;
                [x,y] = meshgrid(linspace(-obj.canvasSize(1)/2,obj.canvasSize(1)/2,obj.canvasSize(1)), ...
                    linspace(-obj.canvasSize(2)/2,obj.canvasSize(2)/2,obj.canvasSize(2)));
                % Center the stimulus.
                x = x - obj.centerOffset(1);
                y = y + obj.centerOffset(2);
                distanceMatrix = sqrt(x.^2 + y.^2);
                circle = uint8((distanceMatrix >= obj.apertureDiameter/2) * 255);
                mask = stage.core.Mask(circle);
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end

            if (obj.maskDiameter > 0) % Create mask
                mask = stage.builtin.stimuli.Ellipse();
                mask.position = obj.canvasSize/2 + obj.centerOffset;
                mask.color = obj.backgroundMeans;
                mask.radiusX = obj.maskDiameter/2;
                mask.radiusY = obj.maskDiameter/2;
                p.addStimulus(mask); %add mask
            end
            
            function p = getScenePosition(obj, time, p0)
                if time > 0 && time <= obj.stimTime*1e-3
                    p = p0 + (time*obj.speed*[cos(obj.orientationRads) sin(obj.orientationRads)]);
                else
                    p = p0;
                end
            end
            
            function p = getScenePositionFix(obj, time, p0)
                if time > 0 && time <= obj.waitTime*1e-3
                    p = p0 + (time*obj.speed*[cos(obj.orientationRads) sin(obj.orientationRads)]);
                else
                    p = p0;
                end
            end
            
            %--------------------------------------------------------------
            % Spot.
            spot = stage.builtin.stimuli.Ellipse();
            spot.radiusX = obj.spotRadius;
            spot.radiusY = obj.spotRadius;
            spot.position = obj.canvasSize/2 + obj.centerOffset;
            spot.color = obj.contrast*obj.rgbValues*obj.backgroundIntensity + obj.backgroundIntensity;
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            barVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time > (obj.preTime + obj.waitTime + obj.delayTime) * 1e-3 && state.time <= (obj.preTime + obj.waitTime + obj.flashTime + obj.delayTime) * 1e-3);
            p.addController(barVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the background type for this epoch.
            obj.backgroundType = obj.backgroundTypes{mod(obj.numEpochsCompleted, length(obj.backgroundTypes))+1};
            epoch.addParameter('backgroundType',obj.backgroundType);
            % Get the delay time.
            obj.delayTime = obj.delayTimes(mod(obj.numEpochsCompleted, length(obj.delayTimes))+1);
            epoch.addParameter('delayTime',obj.delayTime);
            
            % Get the spot contrast.
            obj.contrast = obj.contrasts(mod(floor(obj.numEpochsCompleted/length(obj.backgroundTypes)), length(obj.contrasts))+1);
            
            % Seed the random number generator.
            if obj.randomSeed
                obj.seed = RandStream.shuffleSeed; % Generate a random seed.
            else
                obj.seed = 1; % Repeating seed.
            end
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            epoch.addParameter('seed',obj.seed);
            % Get a random orientation for movement.
            if strcmp(obj.surroundClass,'natural image')
                obj.orientationRads = obj.noiseStream.rand*2*pi;
            else
                obj.orientationRads = 0;
            end
            epoch.addParameter('orientationRads',obj.orientationRads);
            
            % Save the parameters.
            epoch.addParameter('imageName', obj.imageName);
            epoch.addParameter('subjectName', obj.subjectName);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('magnificationFactor', obj.magnificationFactor);
            epoch.addParameter('currentStimSet',obj.currentStimSet);
            epoch.addParameter('contrast', obj.contrast);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end