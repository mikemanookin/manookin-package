classdef RandomWalkColor < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 200                   % Stimulus leading duration (ms)
        moveTime = 180000               % Stimulus duration (ms)
        tailTime = 200                  % Stimulus trailing duration (ms)
        waitTime = 3000                 % Stimulus wait duration (ms)
        stimulusClass = 'bar'           % Stimulus class ('bar' or 'spot')
        stimulusDiameter = 200          % Spot diameter in microns
        contrasts = [-0.2,0.2]          % Spot contrasts
        stimulusSpeed = 500             % Spot speed (std) in microns/second
        chromaticClass = 'chromatic'    % The chromatic class of the background
        chromaticStimulus = false       % Whether the spot/bar is the same color as the background
        correlationClass = 'HMM'
        backgroundIntensity = 0.5
        repeatingSeed = false
        onlineAnalysis = 'none'         % Type of online analysis
        numberOfAverages = uint16(10)   % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        contrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','chromatic'})
        stimulusIndicesType = symphonyui.core.PropertyType('denserealdouble','matrix')
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'bar','spot'})
        correlationClassType = symphonyui.core.PropertyType('char', 'row', {'HMM','OU'})
        spotRadiusPix
        contrast
        stimulusSpeedPix
        spotPositions
        backgroundConditions
        backgroundCondition
        seed
        bgMeans
        rgbContrasts
        backgroundMean
        rgb_contrast
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
            
            % Get the spot diameter in pixels.
            obj.spotRadiusPix = obj.stimulusDiameter / 2 / obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            % Motion per frame
            obj.stimulusSpeedPix = obj.stimulusSpeed / 60 / obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            
            obj.seed = 1;
            
            % Compute the background means.
            [m, delta_rgb] = obj.computeMeans();
            
            if strcmp(obj.chromaticClass, 'achromatic')
                obj.backgroundConditions = {'achromatic'};
                obj.bgMeans = m(2,:);
                obj.rgbContrasts = delta_rgb(2,:);
            else
                obj.backgroundConditions = {'blue','achromatic','yellow'};
                obj.bgMeans = m;
                obj.rgbContrasts = delta_rgb;
            end
        end
        
        function [m,d] = computeMeans(obj)
            % Flux with no manipulation.
%             flux = sum(obj.quantalCatch(:,1:3),1);
%             flux = flux / max(flux);
%             backgrounds = [
%                 0.9046, 1, 0.7563; % Blue sky (3.17 more at 450nm than 600nm)
%                 1, 0.875, 0.385; % White
%                 1, 1, 0.1; % Green/Yellow
%                 ];
            
            m = [
                0.17, 0.57, 0.75;
                0.4, 0.5, 0.7;
                0.55, 0.5, 0.15;
                ];
            
%             m = zeros(size(backgrounds,1),3);
%             for jj = 1 : size(backgrounds,1)
%                 cone_delta = backgrounds(jj,:) - flux;
%                 deltaRGB = (obj.quantalCatch(:,1:3)')' \ cone_delta(:);
%                 deltaRGB = deltaRGB / max(abs(deltaRGB));
%                 m(jj,:) = (1 + deltaRGB)/4;
%                 m(jj,:) = m(jj,:) / max(m(jj,:))*0.5;
%             end
            
            % Get the RGB modulations.
            if obj.chromaticStimulus
                d = ones(size(m));
            else
                d = ones(size(m));
            end
            
            % Match the L/M cone contrast to the requsted contrast value.
%             whitePt = [1, 0.875, 0.385]*0.5;
%             meanFlux = (deltaRGB(:)*ones(1,3)) .* obj.quantalCatch(:,1:3);
        end
        
        function cWeber = getConeContrasts(obj, gunMeans, deltaRGB)
            meanFlux = (gunMeans(:)*ones(1,3)) .* obj.quantalCatch(:,1:3);

            iDelta = sum((deltaRGB(:)*ones(1,3)) .* meanFlux);
            % Calculate the max contrast of each cone type. (Weber contrast)
            cWeber = iDelta ./ sum(meanFlux,1);
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundMean);
            
            if obj.chromaticStimulus
                ct = obj.contrast * obj.rgb_contrast .* obj.backgroundMean + obj.backgroundMean;
            else
                ct = obj.contrast * [0.4, 0.5, 0.7] + [0.4, 0.5, 0.7];
            end
            if strcmp(obj.stimulusClass,'bar')
                spot = stage.builtin.stimuli.Rectangle();
                spot.size = [obj.canvasSize(1), obj.spotRadiusPix*2];
                spot.position = obj.canvasSize/2;
                spot.orientation = 0;
                spot.color = ct; 
            else
                % Add the spots.
                spot = stage.builtin.stimuli.Ellipse();
                spot.radiusX = obj.spotRadiusPix;
                spot.radiusY = obj.spotRadiusPix;
                spot.position = obj.canvasSize/2;
                spot.color = ct; 
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
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
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            bg_idx = mod(obj.numEpochsCompleted,length(obj.backgroundConditions))+1;
            obj.backgroundCondition = obj.backgroundConditions{bg_idx};
            obj.backgroundMean = obj.bgMeans(bg_idx,:);
            obj.rgb_contrast = obj.rgbContrasts(bg_idx,:);
            
            if obj.repeatingSeed
                obj.seed = 1;
            else
                seedIdx = mod(obj.numEpochsCompleted,length(obj.contrasts)*length(obj.backgroundConditions))+1;
                if seedIdx == 1
                    obj.seed = RandStream.shuffleSeed;
                end
            end
            
            if strcmp(obj.correlationClass, 'OU')
                obj.spotPositions = obj.getOUTrajectory(obj.stimTime*1e-3+2, obj.seed, 'motionSpeed', obj.stimulusSpeed);
            else
                obj.spotPositions = manookinlab.util.getHMMTrajectory2d(obj.stimTime*1e-3+2, obj.seed, 'motionSpeed', obj.stimulusSpeed);
            end
            % Get the spot contrast.
            obj.contrast = obj.contrasts(mod(floor(obj.numEpochsCompleted/length(obj.backgroundConditions)),length(obj.contrasts))+1);
            
            % Save the parameters.
            epoch.addParameter('contrast',obj.contrast);
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('backgroundCondition',obj.backgroundCondition)
            %epoch.addParameter('spotX',obj.spotPositions(:,1)');
            %epoch.addParameter('spotY',obj.spotPositions(:,2)');
        end
        
        function positions = getOUTrajectory(duration, seed, varargin)
            ip = inputParser();
            ip.addParameter('correlationTime', 20, @(x)isfloat(x));
            ip.addParameter('frameRate', 60.0, @(x)isfloat(x));
            ip.addParameter('motionSpeed', 700.0, @(x)isfloat(x)); % Motion speed in pixels / sec

            % Parse the inputs.
            ip.parse(varargin{:});

            % Get the field names from the input parser.
            fnames = fieldnames(ip.Results);

            % Create the parameters structure.
            params = struct();
            for jj = 1 : length(fnames)
                params.(fnames{jj}) = ip.Results.(fnames{jj});
            end
            
            dt = 1 / params.frameRate;
            T = 0 : dt : (duration+40)-dt;
            positionStream = RandStream('mt19937ar', 'Seed', seed);

            D_OU = 2.7e6; %dynamical range
            omega = params.correlationTime/2.12;   % omega = G/(2w)=1.06; follow Bielak's overdamped dynamics/ 2015PNAS

            % Get your position vector (x,y).
            positions = zeros(length(T), 2);
            % Velocity vectors (x,y)
            V = zeros(length(T), 2);
            v_noise = positionStream.randn(length(T), 2);

            % Update the velocities and positions on each time step according to the
            % OU algorithm.
            for t = 1 : length(T)-1
                positions(t+1,:) = (1-dt*params.correlationTime/(2.12)^2)*positions(t,:)+sqrt(dt*D_OU) * v_noise(t,:);
            end

            speed = sqrt(sum(diff(positions).^2,2));
            % Get a smoothed estimate of the speed.
            % speed = sqrt(sum(diff(movmean(positions,15)).^2,2));
            avgSpeed = mean(speed)*params.frameRate;

            % Adjust the values to the indicated speed.
            positions = params.motionSpeed*positions/avgSpeed;

            % Get the frames for presentation from the end.
            positions = positions(end-(ceil(duration*params.frameRate))+1:end,:);
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
