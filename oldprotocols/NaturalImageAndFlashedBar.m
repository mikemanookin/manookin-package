classdef NaturalImageAndFlashedBar < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 5000                 % Stimulus duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        waitTime = 4500                 % Stimulus wait duration (ms)
        flashTime = 250                 % Bar flash time (ms)
        barSize = [250 250]             % Bar size [w, h] (pix).
        barContrast = 0.3               % Bar contrast (-1:1)
        barOrientation = 0.0            % Bar orientation in degrees
        motionSD = 30                   % Motion standard dev (pixels)
        stimulusIndex = 2               % Stimulus number (1:161)
        maskDiameter = 125              % Mask diameter in pixels
        apertureDiameter = 2000         % Aperture diameter in pixels.
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        onlineAnalysis = 'extracellular'         % Type of online analysis
        numberOfAverages = uint16(12)    % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        imageMatrix
        backgroundIntensity
        xTraj
        yTraj
        timeTraj
        imageName
        subjectName
        magnificationFactor
        currentStimSet
        orientationRads
        backgroundTypes = {'uniform','natural motion'}
        backgroundType
        seed
        noiseStream
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('manookinlab.figures.ResponseFigure', obj.rig.getDevices('Amp'), ...
                'numberOfAverages', obj.numberOfAverages);
            
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',[0 0 0; 1 0.2 0],...
                'groupBy',{'backgroundType'});
            
            obj.muPerPixel = 0.8;
            obj.orientationRads = obj.barOrientation/180*pi;
        end
        
        function getImageSubject(obj)
            % Get the resources directory.
            tmp = strsplit(pwd,'\');
            pkgDir = [tmp{1},'\',tmp{2},'\',tmp{3},'\Documents\GitRepos\Symphony2\manookin-package\'];
            
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
            
            %get appropriate eye trajectories, at 200Hz
            %full FEM trajectories during fixations
            obj.xTraj = im.FEMdata(obj.stimulusIndex).eyeX;
            obj.yTraj = im.FEMdata(obj.stimulusIndex).eyeY;
            
            % Get the time vector. 
            obj.timeTraj = (0:(length(obj.xTraj)-1)) ./ 200; %sec
            % Gaussian fixational motion...
            xt = 310;
            yt = 310;
            dx = obj.motionSD*obj.noiseStream.randn(size(obj.xTraj));
            dx(1)=0;
            for k = 2 : length(dx)
%                 if k == 2
%                     if dx(k) > 0
%                         dx = abs(dx);
%                     else
%                         dx = -abs(dx);
%                     end
%                 end
                if (sum(dx(1:k)) >= xt) || (sum(dx(1:k)) <= -xt)
                    dx(k:end) = -dx(k:end);
                end
            end
            % Stop moving before the flash.
            dx(obj.timeTraj >= obj.waitTime*1e-3) = 0;
            obj.xTraj = 768+cumsum(dx);
            dy = obj.motionSD*obj.noiseStream.randn(size(obj.yTraj));
            dy(1)=0;
            for k = 2 : length(dy)
%                 if k == 2
%                     if dy(k) > 0
%                         dy = abs(dy);
%                     else
%                         dy = -abs(dy);
%                     end
%                 end
                if (sum(dy(1:k)) >= yt) || (sum(dy(1:k)) <= -yt)
                    dy(k:end) = -dy(k:end);
                end
            end
            % Stop moving before the flash.
            dy(obj.timeTraj >= obj.waitTime*1e-3) = 0;
            obj.yTraj = 512+cumsum(dy);
            
%             obj.xTraj = obj.xTraj(1)+cumsum(obj.motionSD*obj.noiseStream.randn(size(obj.xTraj)));
%             obj.yTraj = obj.yTraj(1)+cumsum(obj.motionSD*obj.noiseStream.randn(size(obj.yTraj)));
            
           
            %need to make eye trajectories for PRESENTATION relative to the center of the image and
            %flip them across the x axis: to shift scene right, move
            %position left, same for y axis - but y axis definition is
            %flipped for DOVES data (uses MATLAB image convention) and
            %stage (uses positive Y UP/negative Y DOWN), so flips cancel in
            %Y direction
            obj.xTraj = -(obj.xTraj - 1536/2); %units=VH pixels
            obj.yTraj = (obj.yTraj - 1024/2);
            
            %also scale them to canvas pixels. 1 VH pixel = 1 arcmin = 3.3
            %um on monkey retina
            %canvasPix = (VHpix) * (um/VHpix)/(um/canvasPix)
            obj.xTraj = obj.xTraj .* 3.3/obj.muPerPixel;
            obj.yTraj = obj.yTraj .* 3.3/obj.muPerPixel;
            
            % Load the fixations for the image.
            f = load([pkgDir,'resources\doves\fixations\', obj.imageName, '.mat']);
            obj.subjectName = f.subj_names_list{im.FEMdata(obj.stimulusIndex).SubjectIndex};
            
            % Get the magnification factor. Exps were done with each pixel
            % = 1 arcmin == 1/60 degree; 200 um/degree...
            obj.magnificationFactor = round(1/60*200/obj.muPerPixel);
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            if strcmp(obj.backgroundType, 'natural motion')
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
                scenePosition = stage.builtin.controllers.PropertyController(scene,...
                    'position', @(state)getScenePosition(obj, state.time - obj.preTime*1e-3, p0));
                % Add the controller.
                p.addController(scenePosition);

                sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(sceneVisible);

                %--------------------------------------------------------------
                % Size is 0 to 1
                sz = (obj.apertureDiameter)/min(obj.canvasSize);
                % Create the outer mask.
                if sz < 1
                    aperture = stage.builtin.stimuli.Rectangle();
                    aperture.position = obj.canvasSize/2;
                    aperture.color = obj.backgroundIntensity;
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
                    mask.color = obj.backgroundIntensity;
                    mask.radiusX = obj.maskDiameter/2;
                    mask.radiusY = obj.maskDiameter/2;
                    p.addStimulus(mask); %add mask
                end
            end
            
            function p = getScenePosition(obj, time, p0)
                if time < 0
                    p = p0;
                elseif time > obj.timeTraj(end) %out of eye trajectory, hang on last frame
                    p(1) = p0(1) + obj.xTraj(end);
                    p(2) = p0(2) + obj.yTraj(end);
                else %within eye trajectory and stim time
                    dx = interp1(obj.timeTraj,obj.xTraj,time);
                    dy = interp1(obj.timeTraj,obj.yTraj,time);
                    p(1) = p0(1) + dx;
                    p(2) = p0(2) + dy;
                end
            end
            
            %--------------------------------------------------------------
            % Moving bar.
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.barSize;
            rect.position = obj.canvasSize/2 + obj.centerOffset;
            rect.orientation = obj.barOrientation;
            rect.color = obj.barContrast*obj.backgroundIntensity + obj.backgroundIntensity;
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect);
            
            barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time > (obj.preTime + obj.waitTime) * 1e-3 && state.time <= (obj.preTime + obj.waitTime + obj.flashTime) * 1e-3);
            p.addController(barVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the background type for this epoch.
            obj.backgroundType = obj.backgroundTypes{mod(obj.numEpochsCompleted, length(obj.backgroundTypes))+1};
            epoch.addParameter('backgroundType',obj.backgroundType);
            
            % Seed the random number generator.
            obj.seed = RandStream.shuffleSeed; % Generate a random seed.
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            epoch.addParameter('seed',obj.seed);
            
            % Get the image and subject names.
            obj.getImageSubject();
            
            % Save the parameters.
            epoch.addParameter('imageName', obj.imageName);
            epoch.addParameter('subjectName', obj.subjectName);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('magnificationFactor', obj.magnificationFactor);
            epoch.addParameter('currentStimSet',obj.currentStimSet);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end