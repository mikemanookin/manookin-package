classdef RandomWalkSpot < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 200                   % Stimulus leading duration (ms)
        moveTime = 30000                 % Stimulus duration (ms)
        tailTime = 200                  % Stimulus trailing duration (ms)
        waitTime = 1000                 % Stimulus wait duration (ms)
        spotDiameter = 200              % Spot diameter in microns
        spotContrasts = [-0.5,0.5]      % Spot contrasts
        spotSpeed = 500 % Spot speed (std) in microns/second
        backgroundSpeed = 500
        stimulusIndices = [2 6 12 15 18 24]         % Stimulus number (1:161)
        stimulusClass = 'spot'           % Stimulus class ('bar' or 'spot')
        backgroundMotionClass = 'gaussian'
        chromaticClass = 'achromatic'
        correlationClass = 'HMM'
        correlationDecayTau = 20        % Correlation decay time constant in msec
        repeatingSeed = false
        onlineAnalysis = 'none'% Type of online analysis
        numberOfAverages = uint16(48)   % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        spotContrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        backgroundMotionClassType = symphonyui.core.PropertyType('char', 'row', {'natural','gaussian'})
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','blue','yellow'})
        stimulusIndicesType = symphonyui.core.PropertyType('denserealdouble','matrix')
        correlationClassType = symphonyui.core.PropertyType('char', 'row', {'HMM','OU'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'bar','spot'})
        imageMatrix
        backgroundIntensity
        xTraj
        yTraj
        timeTraj
        imageName
        subjectName
        magnificationFactor
        currentStimSet
        stimulusIndex
        pkgDir
        im
        spotRadiusPix
        spotContrast
        spotSpeedPix
        backgroundSpeedPix
        spotPositions
        backgroundRng
        freezeFEMs = false
        backgroundConditions
        backgroundCondition
        seed
        stimulusConditions = {'object','uncorrelated','correlated'}
        stimulusCondition
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.ResponseFigure', obj.rig.getDevices('Amp'), ...
                    'numberOfAverages', obj.numberOfAverages);

                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',[0 0 0]);
            end
            
            % Get the resources directory.
            obj.pkgDir = manookinlab.Package.getResourcePath();
            
            obj.currentStimSet = 'dovesFEMstims20160826.mat';
            
            % Load the current stimulus set.
            obj.im = load([obj.pkgDir,'\',obj.currentStimSet]);
            
            % Get the spot diameter in pixels.
            obj.spotRadiusPix = obj.spotDiameter / 2 / obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            % Motion per frame
            obj.spotSpeedPix = obj.spotSpeed / 60 / obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            obj.backgroundSpeedPix = obj.backgroundSpeed / 60 / obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            
            % Get the image and subject names.
            if length(unique(obj.stimulusIndices)) == 1
                obj.stimulusIndex = unique(obj.stimulusIndices);
                obj.getImageSubject();
            end
            obj.seed = 1;
            
            if strcmp(obj.backgroundMotionClass, 'gaussian')
                obj.backgroundConditions = {'stationary','motion-gaussian','motion-gaussian'};
            else
                obj.backgroundConditions = {'stationary','motion-natural','motion-natural'};
            end
        end
        
        function getImageSubject(obj)
            % Get the image name.
            obj.imageName = obj.im.FEMdata(obj.stimulusIndex).ImageName;
            
            % Load the image.
            fileId = fopen([obj.pkgDir,'\doves\images\', obj.imageName],'rb','ieee-be');
            img = fread(fileId, [1536 1024], 'uint16');
            fclose(fileId);
            
            img = double(img');
            img = (img./max(img(:))); %rescale s.t. brightest point is maximum monitor level
            obj.backgroundIntensity = mean(img(:));%set the mean to the mean over the image
            
            switch obj.chromaticClass
                case 'blue'
                    img = repmat(img,[1,1,3]);
                    img(:,:,1:2) = obj.backgroundIntensity;
                case 'yellow'
                    img = repmat(img,[1,1,3]);
                    img(:,:,3) = obj.backgroundIntensity;
                otherwise
                    img = img.*255; %rescale s.t. brightest point is maximum monitor level
            end
            obj.imageMatrix = uint8(img);
            
            if strcmp(obj.backgroundCondition,'motion-natural')
                obj.xTraj = obj.im.FEMdata(obj.stimulusIndex).eyeX;
                obj.yTraj = obj.im.FEMdata(obj.stimulusIndex).eyeY;
                obj.timeTraj = (0:(length(obj.xTraj)-1)) ./ 200; %sec
                
                % Make sure you don't run out of time.
                nReps = ceil(obj.moveTime*1e-3 / max(obj.timeTraj(:)));
                if nReps > 1
                    xt = obj.xTraj;
                    yt = obj.yTraj;
                    t = obj.timeTraj;
                    for tt = 2:nReps
                        if mod(tt,2) == 0
                            xt = [xt,fliplr(obj.xTraj(:)')]; %#ok<AGROW>
                            yt = [yt,fliplr(obj.yTraj(:)')]; %#ok<AGROW>
                        else
                            xt = [xt,obj.xTraj(:)']; %#ok<AGROW>
                            yt = [yt,obj.yTraj(:)']; %#ok<AGROW>
                        end
                        t = [t,t(end)+obj.timeTraj(:)']; %#ok<AGROW>
                    end
                    obj.xTraj = xt;
                    obj.yTraj = yt;
                    obj.timeTraj = t;
                end

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
                obj.xTraj = obj.xTraj .* 3.3/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
                obj.yTraj = obj.yTraj .* 3.3/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            end
            
            
            
            % Load the fixations for the image.
            f = load([obj.pkgDir,'\doves\fixations\', obj.imageName, '.mat']);
            obj.subjectName = f.subj_names_list{obj.im.FEMdata(obj.stimulusIndex).SubjectIndex};
            
            % Get the magnification factor. Exps were done with each pixel
            % = 1 arcmin == 1/60 degree; 200 um/degree...
            obj.magnificationFactor = round(1/60*200/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel'));
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create your scene.
            scene = stage.builtin.stimuli.Image(obj.imageMatrix);
            scene.size = [size(obj.imageMatrix,2) size(obj.imageMatrix,1)]*obj.magnificationFactor;
            p0 = obj.canvasSize/2;
            scene.position = p0;
            
            scene.setMinFunction(GL.NEAREST);
            scene.setMagFunction(GL.NEAREST);
            
            % Add the stimulus to the presentation.
            p.addStimulus(scene);
            
            %apply eye trajectories to move image around
            if strcmp(obj.backgroundCondition, 'motion-gaussian')
                scenePositionG = stage.builtin.controllers.PropertyController(scene,...
                    'position', @(state)getScenePositionGauss(obj, state.time - (obj.preTime+obj.waitTime)/1e3));
                % Add the controller.
                p.addController(scenePositionG);
            elseif strcmp(obj.backgroundCondition, 'motion-natural')
                scenePosition = stage.builtin.controllers.PropertyController(scene,...
                    'position', @(state)getScenePosition(obj, state.time - (obj.preTime+obj.waitTime)/1e3, p0));
                % Add the controller.
                p.addController(scenePosition);
            end
            
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);
            
            % Add the spot.
            if strcmp(obj.stimulusClass,'bar')
                spot = stage.builtin.stimuli.Rectangle();
                spot.size = [obj.canvasSize(1), obj.spotRadiusPix*2];
                spot.position = obj.canvasSize/2;
                spot.orientation = 0;
                spot.color = obj.backgroundIntensity*obj.spotContrast + obj.backgroundIntensity; 
            else
                % Add the spots.
                spot = stage.builtin.stimuli.Ellipse();
                spot.radiusX = obj.spotRadiusPix;
                spot.radiusY = obj.spotRadiusPix;
                spot.position = obj.canvasSize/2;
                spot.color = obj.backgroundIntensity*obj.spotContrast + obj.backgroundIntensity; 
            end
%             spot = stage.builtin.stimuli.Ellipse();
%             spot.radiusX = obj.spotRadiusPix;
%             spot.radiusY = obj.spotRadiusPix;
%             spot.position = obj.canvasSize/2;
%             spot.color = obj.backgroundIntensity*obj.spotContrast + obj.backgroundIntensity; 
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
%             spotPosition = stage.builtin.controllers.PropertyController(spot,...
%                 'position', @(state)getSpotPosition(obj, state.time - (obj.preTime+obj.waitTime)/1e3));
%             spotPosition = stage.builtin.controllers.PropertyController(spot,...
%                 'position', @(state)getSpotPosition(obj, state.frame - ceil((obj.preTime+obj.waitTime)/1e3*60)));
%             p.addController(spotPosition);
            
            if strcmp(obj.stimulusClass,'bar')
                spotPosition = stage.builtin.controllers.PropertyController(spot,...
                    'position', @(state)getBarPosition(obj, state.frame - ceil((obj.preTime+obj.waitTime)/1e3*60)));
            else
                spotPosition = stage.builtin.controllers.PropertyController(spot,...
                    'position', @(state)getSpotPosition(obj, state.frame - ceil((obj.preTime+obj.waitTime)/1e3*60)));
            end
            p.addController(spotPosition);
            
            function p = getBarPosition(obj, frame)
                if frame > 0 
                    p = [0,obj.spotPositions(frame,2)]+obj.canvasSize/2;
                else
                    p = obj.canvasSize/2;
                end
            end
            
            function p = getSpotPosition(obj, frame)
                if frame > 0 
                    p = obj.spotPositions(frame,:)+obj.canvasSize/2;
                else
                    p = obj.canvasSize/2;
                end
            end
            
%             function p = getSpotPosition(obj, time)
%                 persistent lastP
%                 if isempty(lastP)
%                     lastP = obj.canvasSize/2;
%                 end
%                 if time > 0 && time <= obj.moveTime*1e-3
%                     lastP = lastP + obj.backgroundSpeedPix*obj.spotRng.randn(1,2);
%                 else
%                     lastP = obj.canvasSize/2;
%                 end
%                 p = lastP;
%             end
            
            function p = getScenePositionGauss(obj, time)
                persistent lP
                if isempty(lP)
                    lP = obj.canvasSize/2;
                end
                if time > 0 && time <= obj.moveTime*1e-3
                    lP = lP + obj.backgroundSpeedPix*obj.backgroundRng.randn(1,2);
                else
                    lP = obj.canvasSize/2;
                end
                p = lP;
            end
            
            function p = getScenePosition(obj, time, p0)
                if time < 0
                    p = p0;
                elseif time > obj.timeTraj(end) %out of eye trajectory, hang on last frame
                    p(1) = p0(1) + obj.xTraj(end);
                    p(2) = p0(2) + obj.yTraj(end);
                else %within eye trajectory and stim time
                    [~,ix] = min(abs(obj.timeTraj-time));
                    dx = obj.xTraj(ix);
                    dy = obj.yTraj(ix);
                    p(1) = p0(1) + dx;
                    p(2) = p0(2) + dy;
                end
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.backgroundCondition = obj.backgroundConditions{mod(obj.numEpochsCompleted,length(obj.backgroundConditions))+1};
            obj.stimulusCondition = obj.stimulusConditions{mod(obj.numEpochsCompleted,length(obj.stimulusConditions))+1};
            
            if length(unique(obj.stimulusIndices)) > 1
                % Set the current stimulus trajectory.
                obj.stimulusIndex = obj.stimulusIndices(mod(floor(obj.numEpochsCompleted/(length(obj.spotContrasts)*length(obj.backgroundConditions))),...
                    length(obj.stimulusIndices)) + 1);
                obj.getImageSubject();
            end
            
            if obj.repeatingSeed
                obj.seed = 1;
            else
                seedIdx = mod(obj.numEpochsCompleted,length(obj.spotContrasts)*length(obj.backgroundConditions))+1;
                if seedIdx == 1
                    obj.seed = RandStream.shuffleSeed;
                end
            end
            
            if strcmp(obj.correlationClass, 'OU')
                obj.spotPositions = manookinlab.util.getOUTrajectory2d(obj.stimTime*1e-3+2, obj.seed, 'motionSpeed', obj.spotSpeed, 'correlationDecayTau', obj.correlationDecayTau);
            else
                obj.spotPositions = manookinlab.util.getHMMTrajectory2d(obj.stimTime*1e-3+2, obj.seed, 'motionSpeed', obj.spotSpeed, 'correlationDecayTau', obj.correlationDecayTau);
            end
%             obj.spotPositions = manookinlab.util.getHMMTrajectory2d(obj.stimTime*1e-3+2, obj.seed, 'motionSpeed', obj.spotSpeed);
            obj.backgroundRng = RandStream('mt19937ar', 'Seed', obj.seed+10);
            
            % Adjust the position if the spot and background are correlated
            if strcmp(obj.stimulusCondition,'correlated')
                obj.spotPositions = obj.spotPositions + obj.backgroundSpeedPix*obj.backgroundRng.randn(size(obj.spotPositions,1),2);
                % Reseed
                obj.backgroundRng = RandStream('mt19937ar', 'Seed', obj.seed+10);
            end
            
            % Get the spot contrast.
            obj.spotContrast = obj.spotContrasts(mod(floor(obj.numEpochsCompleted/length(obj.backgroundConditions)),length(obj.spotContrasts))+1);
            
            % Save the parameters.
            epoch.addParameter('stimulusCondition',obj.stimulusCondition);
            epoch.addParameter('stimulusIndex', obj.stimulusIndex);
            epoch.addParameter('imageName', obj.imageName);
            epoch.addParameter('subjectName', obj.subjectName);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('magnificationFactor', obj.magnificationFactor);
            epoch.addParameter('currentStimSet',obj.currentStimSet);
            epoch.addParameter('spotContrast',obj.spotContrast);
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('backgroundCondition',obj.backgroundCondition)
%             epoch.addParameter('spotX',obj.spotPositions(:,1)');
%             epoch.addParameter('spotY',obj.spotPositions(:,2)');
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.waitTime + obj.moveTime;
        end
        
        % Same presentation each epoch in a run. Replay.
%         function controllerDidStartHardware(obj)
%             controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
%             if (obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < obj.numberOfAverages) && (length(unique(obj.stimulusIndices)) == 1)
%                 obj.rig.getDevice('Stage').replay
%             else
%                 obj.rig.getDevice('Stage').play(obj.createPresentation());
%             end
%         end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
