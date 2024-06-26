classdef SaccadeAndPursuitCRF < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        waitTime = 3000                 % Stimulus wait duration (ms)
        flashTime = 250                 % Spot flash time (ms)
        delayTimes = [-300 50 100 200 400]            % Delay time (ms)
        spotRadius = 100                % Spot radius (microns).
        contrasts = [0.2] % Spot contrasts (-1:1)
        speed = 2750                    % Background motion speed (pix/sec)
        stimulusIndex = 2               % Stimulus number (1:161)
        surroundContrast = 1.0          % Surround contrast (0-1)
        surroundBarWidth = 75           % Surround bar width (microns)
        maskRadius = 125                % Mask radius in pixels
        blurMask = false                % Gaussian blur of center mask? (t/f)
        apertureDiameter = 2000         % Aperture diameter in microns.
        randomSeed = false              % Use a random (true) or repeating seed (false)
        backgroundIntensity = 0.5       % Mean background intenstiy
        centerClass = 'spot'            % Center stimulus class
        surroundClass = 'sine grating'  % Background stimulus type.
        chromaticClass = 'achromatic'   % Spot color
        bgChromaticClass = 'achromatic' % Background color
        onlineAnalysis = 'extracellular' % Type of online analysis
        stimulusSequence = 'saccade'    % Interleaved sequence types.
        numberOfAverages = uint16(120)    % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Hidden)
        ampType
        centerClassType = symphonyui.core.PropertyType('char', 'row', {'spot','high freq grating', 'low freq grating'})
        surroundClassType = symphonyui.core.PropertyType('char', 'row', {'square grating','sine grating','gaussian texture','chirp grating','pink grating','random grating','natural image','plaid'})
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','red-green isoluminant','red-green isochromatic'})
        bgChromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','red-green isoluminant','red-green isochromatic'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stimulusSequenceType = symphonyui.core.PropertyType('char', 'row', {'tremor-saccade','pursuit-saccade','tremor','saccade'})
        contrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        delayTimesType = symphonyui.core.PropertyType('denserealdouble','matrix')
        imageMatrix
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
        xyTable
        surroundBarWidthPix
        spotRadiusPix
        maskRadiusPix
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            if length(unique(obj.delayTimes)) > 1
                obj.backgroundTypes = {'stationary','fixation'};
            else
                obj.backgroundTypes = {'stationary','pursuit','fixation'};
            end
            
            switch obj.stimulusSequence
                case 'tremor-saccade'
                    obj.backgroundTypes = {'stationary','saccade','tremor'};
                case 'pursuit-saccade'
                    obj.backgroundTypes = {'stationary','pursuit','saccade'};
                case 'tremor'
                    obj.backgroundTypes = {'stationary','tremor'};
                case 'saccade'
                    obj.backgroundTypes = {'stationary','saccade'};
            end
            
            if ~strcmp(obj.onlineAnalysis,'none')
                obj.showFigure('manookinlab.figures.ContrastResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'preTime',obj.preTime+obj.waitTime+obj.delayTimes(1),...
                    'stimTime',obj.flashTime,...
                    'contrasts',unique(obj.contrasts),...
                    'groupBy','backgroundType',...
                    'groupByValues',obj.backgroundTypes,...
                    'temporalClass','pulse');
            end
            
            obj.muPerPixel = 0.8;
            obj.surroundBarWidthPix = obj.rig.getDevice('Stage').um2pix(obj.surroundBarWidth);
            obj.spotRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.spotRadius);
            obj.maskRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.maskRadius);
%             gridSizePix = obj.rig.getDevice('Stage').um2pix(obj.gridSize);
            
            % Get the image and subject names.
            switch obj.surroundClass
                case 'natural image'
                    obj.getImageSubject();
                case 'plaid'
                    obj.getPlaid();
                case {'square grating','sine grating'}
                    obj.getGrating();
                case 'gaussian texture'
                    obj.getGaussianTexture();
                case 'chirp grating'
                    obj.getChirpGrating();
            end
            
            if strcmp(obj.surroundClass, 'pink grating')
                obj.seed = 1;
                obj.getPinkGrating();
            elseif strcmp(obj.surroundClass, 'random grating')
                obj.seed = 1;
                obj.getRandomGrating();
            end
            
            if strcmp(obj.stageClass,'LightCrafter')
                obj.chromaticClass = 'achromatic';
            end
            
            % Check the color space.
            if strcmp(obj.chromaticClass,'achromatic')
                obj.rgbMeans = obj.backgroundIntensity;
                obj.rgbValues = 1;
                obj.backgroundMeans = obj.backgroundIntensity*ones(1,3);
            else
                [obj.rgbMeans, ~, deltaRGB] = getMaxContrast(obj.quantalCatch, obj.chromaticClass);
                obj.rgbValues = deltaRGB*obj.backgroundIntensity + obj.backgroundIntensity;
                obj.backgroundMeans = obj.rgbMeans(:)' * obj.backgroundIntensity / 0.5;
            end
            
            if ~strcmp(obj.bgChromaticClass,'achromatic')
                [rgMeans, ~, deltaRGB] = getMaxContrast(obj.quantalCatch, obj.bgChromaticClass);
                rgMeans = rgMeans * obj.backgroundIntensity / 0.5;
                % Convert the image back to pixel values.
                imgTmp = 2*(double(obj.imageMatrix)/255) - 1;
                imgTmp = 255*imgTmp;
                obj.imageMatrix = repmat(double(obj.imageMatrix), [1 1 3]);
                for k = 1 : 2
                    obj.imageMatrix(:,:,k) = imgTmp*deltaRGB(k)*rgMeans(k) + rgMeans(k);
                end
                obj.imageMatrix(:,:,3) = 0;
                obj.imageMatrix = uint8(obj.imageMatrix);
            end
        end
        
        function getTremorSequence(obj)
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            nframes = ceil(obj.stimTime * obj.frameRate) + 10;
            xy = obj.noiseStream.randn(nframes,2)*obj.speed/obj.frameRate;            
            obj.xyTable = obj.canvasSize/2 + cumsum(xy);
        end
        
        function getPlaid(obj)
            
            [x,y] = meshgrid(...
                linspace(-1536/2, 1536/2, 1536), ...
                linspace(-1024/2, 1024/2, 1024));
            
            x = x / (obj.surroundBarWidth*2/obj.magnificationFactor) * 2 * pi;
            y = y / (obj.surroundBarWidth*2/obj.magnificationFactor) * 2 * pi;
            
            % Calculate the raw plaid image.
            img = obj.surroundContrast*sign(cos((cos(pi)*x + sin(pi) * y)) + cos((cos(pi/2)*x + sin(pi/2) * y)));
            
            img = obj.backgroundIntensity*img + obj.backgroundIntensity;
            
            img = img*255; %rescale s.t. brightest point is maximum monitor level
            obj.imageMatrix = uint8(img);
        end
        
        function getGrating(obj)
            w = 2*912*2+(2*obj.speed/obj.frameRate);
            x = linspace(-w/2+1, w/2, w);
            
            sf = length(x)/(obj.surroundBarWidthPix*2);
            x = x/max(x);
            
            x = x * sf * 2 * pi;
%             x = x / (obj.surroundBarWidthPix*2) * 2 * pi;
            x = repmat(x,[512 1]);
            
            % Calculate the raw grating image.
            if strcmp(obj.surroundClass,'square grating')
                img = obj.surroundContrast*sign(sin(x));
            else
                img = obj.surroundContrast*sin(x);
            end
            
            img = obj.backgroundIntensity*img + obj.backgroundIntensity;
            
            img = img*255; %rescale s.t. brightest point is maximum monitor level
            obj.imageMatrix = uint8(img);
        end
        
        function getGaussianTexture(obj)
            DIM = 2000;
            img = manookinlab.util.generateTexture(DIM, obj.surroundBarWidth/obj.magnificationFactor, 1);
%             img = img(100+(1:512),:);
            img = img(1,:);
            img = repmat(img,[512 1]);
%             img(241:272,(810:841)+175) = 0.5;
            img(:,(800:851)+175) = 0.5;
            img = obj.surroundContrast * (2*img-1);
            img = obj.backgroundIntensity*img + obj.backgroundIntensity;
            
            img = img*255; %rescale s.t. brightest point is maximum monitor level
            obj.imageMatrix = uint8(img);
        end
        
        function getChirpGrating(obj)
            frequencyMin = 1;
            frequencyMax = 1650/(obj.surroundBarWidth*2/obj.magnificationFactor*2);
            frequencyDelta = (frequencyMax - frequencyMin)/2;


            x = linspace(-1, 1, 1650);
            x = obj.surroundContrast*sin(2*pi*(frequencyMin*x+frequencyDelta*x.^2));
            img = repmat(x,[512 1]);
            img = obj.backgroundIntensity*img + obj.backgroundIntensity;
            
            img = img*255; %rescale s.t. brightest point is maximum monitor level
            obj.imageMatrix = uint8(img);
        end
        
        function getPinkGrating(obj)
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            DIM = 1650;
            BETA = -2;
            % First quadrant are positive frequencies.  Zero frequency is at u(1,1).
            u = [(0:floor(DIM/2)) -(ceil(DIM(1)/2)-1:-1:1)]/DIM;
            
            % Generate the power spectrum
            S_f = (u.^2).^(BETA/2);

            % Set any infinities to zero
            S_f(S_f==inf) = 0;

            % Generate a grid of random phase shifts
            phi = 2*obj.noiseStream.rand(size(u)) - 1;
            
            % Zero out the very high frequencies.
%             S_f(133:end-123) = 0;

            % Inverse Fourier transform to obtain the the spatial pattern
            x = ifft(S_f.^0.5 .* (cos(2*pi*phi)+1i*sin(2*pi*phi)));

            % Pick just the real component
            x = real(x);
            img(241:272,810:841) = 0;
            img = repmat(obj.surroundContrast*x/max(abs(x)),[512 1]);
            
            img = obj.backgroundIntensity*img + obj.backgroundIntensity;
            
            img = img*255; %rescale s.t. brightest point is maximum monitor level
            obj.imageMatrix = uint8(img);
        end
        
        function getRandomGrating(obj)
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            DIM = 1650;
            % Generate the power spectrum
            S_f = ones(1,DIM);
            
            % Generate a grid of random phase shifts
            phi = obj.noiseStream.randn(size(S_f));
            
            % Zero out the very high frequencies.
            S_f(133:end-132) = 0;

            % Inverse Fourier transform to obtain the the spatial pattern
            x = ifft(S_f.^0.5 .* (cos(2*pi*phi)+1i*sin(2*pi*phi)));

            % Pick just the real component
            x = real(x);
            img(241:272,810:841) = 0;
            img = repmat(obj.surroundContrast*x/max(abs(x)),[512 1]);
            
            img = obj.backgroundIntensity*img + obj.backgroundIntensity;
            
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
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create your scene.
            scene = stage.builtin.stimuli.Image(obj.imageMatrix);
            scene.size = [size(obj.imageMatrix,2) size(obj.imageMatrix,1)]*obj.magnificationFactor;
            scene.position = obj.canvasSize/2;

            scene.setMinFunction(GL.NEAREST);
            scene.setMagFunction(GL.NEAREST);

            % Add the stimulus to the presentation.
            p.addStimulus(scene);

            %apply eye trajectories to move image around
            if strcmp(obj.backgroundType, 'pursuit')
                scenePosition = stage.builtin.controllers.PropertyController(scene,...
                    'position', @(state)getScenePosition(obj, state.time - obj.preTime*1e-3, obj.canvasSize/2));
                % Add the controller.
                p.addController(scenePosition);
            elseif strcmp(obj.backgroundType,'saccade')
                scenePosition = stage.builtin.controllers.PropertyController(scene,...
                    'position', @(state)getScenePositionFix(obj, state.time - obj.preTime*1e-3, obj.canvasSize/2));
                % Add the controller.
                p.addController(scenePosition);
            elseif strcmp(obj.backgroundType,'tremor')
                scenePosition = stage.builtin.controllers.PropertyController(scene,...
                    'position', @(state)getScenePositionTrem(obj, state.time - obj.preTime*1e-3, obj.canvasSize/2));
                % Add the controller.
                p.addController(scenePosition);
            end

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
                distanceMatrix = sqrt(x.^2 + y.^2);
                circle = uint8((distanceMatrix >= obj.apertureDiameter/2) * 255);
                mask = stage.core.Mask(circle);
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end

            if (obj.maskRadius > 0) % Create mask
                if obj.blurMask
                    mask = stage.builtin.stimuli.Rectangle();
                    mask.position = obj.canvasSize/2;
                    mask.color = obj.backgroundMeans;
                    mask.size = obj.maskRadiusPix*2*ones(1,2);
                    % Assign a gaussian envelope mask to the grating.
                    msk = stage.core.Mask.createGaussianEnvelope(obj.maskRadiusPix*2);
                    mask.setMask(msk);
                else
                    mask = stage.builtin.stimuli.Ellipse();
                    mask.position = obj.canvasSize/2;
                    mask.color = obj.backgroundMeans;
                    mask.radiusX = obj.maskRadiusPix;
                    mask.radiusY = obj.maskRadiusPix;
                end
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
            
            function p = getScenePositionTrem(obj, time, p0)
                if time > 0 && time <= obj.waitTime*1e-3
                    f = floor(time*obj.frameRate)+1;
                    p = obj.xyTable(f,:);
                else
                    p = p0;
                end
            end
            
            %--------------------------------------------------------------
            % Spot.
            spot = stage.builtin.stimuli.Ellipse();
            spot.radiusX = obj.spotRadiusPix;
            spot.radiusY = obj.spotRadiusPix;
            spot.position = obj.canvasSize/2;
            spot.color = obj.contrast*obj.rgbValues.*obj.backgroundMeans + obj.backgroundMeans;
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            barVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time > (obj.preTime + obj.waitTime + obj.delayTime) * 1e-3 && state.time <= (obj.preTime + obj.waitTime + obj.flashTime + obj.delayTime) * 1e-3);
            p.addController(barVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the background type for this epoch.
            obj.backgroundType = obj.backgroundTypes{mod(obj.numEpochsCompleted, length(obj.backgroundTypes))+1};
            epoch.addParameter('backgroundType',obj.backgroundType);
            if strcmp(obj.backgroundType,'tremor')
                obj.getTremorSequence();
            end
            % Get the delay time. 
            obj.delayTime = obj.delayTimes(mod(floor(obj.numEpochsCompleted/length(obj.backgroundTypes)), length(obj.delayTimes))+1);
%             obj.delayTime = obj.delayTimes(mod(obj.numEpochsCompleted, length(obj.delayTimes))+1);
            epoch.addParameter('delayTime',obj.delayTime);
            
            % Get the spot contrast.
            obj.contrast = obj.contrasts(mod(floor(obj.numEpochsCompleted/length(obj.backgroundTypes)), length(obj.contrasts))+1);
            
            % Seed the random number generator.
            if obj.randomSeed
                obj.seed = RandStream.shuffleSeed; % Generate a random seed.
                if strcmp(obj.surroundClass, 'pink grating')
                    obj.getPinkGrating();
                elseif strcmp(obj.surroundClass,'random grating')
                    obj.getRandomGrating();
                end
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
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.waitTime + max(max(obj.delayTimes),250) + obj.flashTime;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end