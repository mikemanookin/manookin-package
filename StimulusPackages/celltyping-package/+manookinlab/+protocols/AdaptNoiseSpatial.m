classdef AdaptNoiseSpatial < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Noise leading duration (ms)
        uniqueTime = 165000             % Duration of unique noise sequence (ms)
        repeatTime = 15000              % Duration of repeating sequence at end of epoch (ms)
        tailTime = 250                  % Noise trailing duration (ms)
        stepDuration = 5000             % Duration series (ms)
        high_fraction = 0.05            % Fraction of pixels that are high contrast on a frame.
        contrastsHigh = [0.3,1.0]       % High contrast values
        contrastsLow = [0.3,0.3]        % Low contrast values
        stixelSizes = [90,90]           % Edge length of stixel (microns)
        gridSize = 30                   % Size of underling grid
        gaussianFilter = false          % Whether to use a Gaussian filter
        filterSdStixels = 1.0           % Gaussian filter standard dev in stixels.
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        frameDwells = uint16([1,1])     % Frame dwell.
        chromaticClass = 'BY'           % Chromatic type
        onlineAnalysis = 'none'
        numberOfAverages = uint16(10)   % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary', 'ternary', 'gaussian'})
        chromaticClassType = symphonyui.core.PropertyType('char','row',{'achromatic','RGB','BY'})
        contrastsHighType = symphonyui.core.PropertyType('denserealdouble','matrix')
        contrastsLowType = symphonyui.core.PropertyType('denserealdouble','matrix')
        stixelSizesType = symphonyui.core.PropertyType('denserealdouble','matrix')
        frameDwellsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        stixelSize
        stepsPerStixel
        numXStixels
        numYStixels
        numXChecks
        numYChecks
        seed
        numFrames
        stixelSizePix
        stixelShiftPix
        imageMatrix
        noiseStream
        positionStream
        noiseStreamRep
        positionStreamRep
        monitor_gamma
        frameDwell
        mask_stream
        num_masks
        contrast_mask
        contrast_high
        contrast_low
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end

    methods
        function didSetRig(obj)
            didSetRig@manookinlab.protocols.ManookinLabStageProtocol(obj);

            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            obj.num_masks = ceil(obj.stimTime / obj.stepDuration)+4;
            
            % Get the number of frames.
            obj.numFrames = floor(obj.stimTime * 1e-3 * obj.frameRate)+15;
            
            if obj.gaussianFilter
                % Get the gamma ramps.
                [r,g,b] = obj.rig.getDevice('Stage').getMonitorGammaRamp();
                obj.monitor_gamma = [r;g;b];
                gamma_scale = 0.5/(0.5539*exp(-0.8589*obj.filterSdStixels)+0.05732);
                new_gamma = 65535*(0.5*gamma_scale*linspace(-1,1,256)+0.5);
                new_gamma(new_gamma < 0) = 0;
                new_gamma(new_gamma > 65535) = 65535;
                obj.rig.getDevice('Stage').setMonitorGammaRamp(new_gamma, new_gamma, new_gamma);
            end            
        end
        
        % Create a Gaussian filter for the stimulus.
        function h = get_gaussian_filter(obj)
%             kernel = fspecial('gaussian',[3,3],obj.filterSdStixels);
            
            p2 = (2*ceil(2*obj.filterSdStixels)+1) * ones(1,2);
            siz   = (p2-1)/2;
            std   = obj.filterSdStixels;

            [x,y] = meshgrid(-siz(2):siz(2),-siz(1):siz(1));
            arg   = -(x.*x + y.*y)/(2*std*std);

            h     = exp(arg);
            h(h<eps*max(h(:))) = 0;

            sumh = sum(h(:));
            if sumh ~= 0
                h  = h/sumh;
            end
        end

 
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            obj.imageMatrix = obj.backgroundIntensity * ones(obj.numYStixels,obj.numXStixels);
            checkerboard = stage.builtin.stimuli.Image(uint8(obj.imageMatrix));
            checkerboard.position = obj.canvasSize / 2;
            checkerboard.size = [obj.numXStixels, obj.numYStixels] * obj.stixelSizePix;

            % Set the minifying and magnifying functions to form discrete
            % stixels.
            checkerboard.setMinFunction(GL.NEAREST);
            checkerboard.setMagFunction(GL.NEAREST);
            
            % Get the filter.
            if obj.gaussianFilter
                kernel = obj.get_gaussian_filter(); %fspecial('gaussian',[3,3],obj.filterSdStixels);

                filter = stage.core.Filter(kernel);
                checkerboard.setFilter(filter);
                checkerboard.setWrapModeS(GL.MIRRORED_REPEAT);
                checkerboard.setWrapModeT(GL.MIRRORED_REPEAT);
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(checkerboard);
            
            gridVisible = stage.builtin.controllers.PropertyController(checkerboard, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(gridVisible);
            
            % Calculate preFrames and stimFrames
            preF = floor(obj.preTime/1000 * 60);

            if ~strcmp(obj.chromaticClass,'achromatic') && isempty(strfind(obj.rig.getDevice('Stage').name, 'LightCrafter'))
                if strcmp(obj.chromaticClass,'BY')
                    imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                        @(state)setBYStixels(obj, state.frame - preF, state.time - obj.preTime*1e-3));
                else
                    imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                        @(state)setRGBStixels(obj, state.frame - preF, state.time - obj.preTime*1e-3));
                end
            else
                imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                    @(state)setStixels(obj, state.frame - preF, state.time - obj.preTime*1e-3));
            end
            p.addController(imgController);
            
            % Position controller
            if obj.stepsPerStixel > 1
                xyController = stage.builtin.controllers.PropertyController(checkerboard, 'position',...
                    @(state)setJitter(obj, state.frame - preF, state.time - obj.preTime*1e-3));
                p.addController(xyController);
            end
            
            function s = setStixels(obj, frame, time)
                persistent M;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        if time < obj.uniqueTime*1e-3
                            mask_idx = floor(time  / (obj.stepDuration*1e-3))+1;
                            M = 2* (obj.noiseStream.rand(obj.numYStixels,obj.numXStixels)>0.5)-1;
                            M = M .* squeeze(obj.contrast_mask(:,:,mask_idx));
                        else
                            M = obj.contrast_low*(2*(obj.noiseStream.rand(obj.numYStixels,obj.numXStixels)>0.5)-1);
                        end
                        M = M*obj.backgroundIntensity + obj.backgroundIntensity;
                    end
                else
                    M = obj.imageMatrix;
                end
                s = uint8(255*M);
            end
            
            % RGB noise
            function s = setRGBStixels(obj, frame, time)
                persistent M;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        if time < obj.uniqueTime*1e-3
                            mask_idx = floor(time  / (obj.stepDuration*1e-3))+1;
                            M = 2*(obj.noiseStream.rand(obj.numYStixels,obj.numXStixels,3)>0.5)-1;
                            M = M .* repmat(obj.contrast_mask(:,:,mask_idx),[1,1,3]);
                        else
                            M = obj.contrast_low*(2*(obj.noiseStream.rand(obj.numYStixels,obj.numXStixels,3)>0.5)-1);
                        end
                        M = M*obj.backgroundIntensity + obj.backgroundIntensity;
                    end
                else
                    M = obj.imageMatrix;
                end
                s = uint8(255*M);
            end
            
            % Blue-Yellow noise
            function s = setBYStixels(obj, frame, time)
                persistent M;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        M = zeros(obj.numYStixels,obj.numXStixels,3);
                        if time < obj.uniqueTime*1e-3
                            mask_idx = floor(time  / (obj.stepDuration*1e-3))+1;% floor(frame/60  / (obj.stepDuration*1e-3))+1;
                            tmpM = 2*(obj.noiseStream.rand(obj.numYStixels,obj.numXStixels,2)>0.5)-1;
                            tmpM = tmpM .* repmat(obj.contrast_mask(:,:,mask_idx),[1,1,2]);
                        else
                            tmpM = obj.contrast_low*(2*(obj.noiseStreamRep.rand(obj.numYStixels,obj.numXStixels,2)>0.5)-1);
                        end
                        tmpM = tmpM*obj.backgroundIntensity + obj.backgroundIntensity;
                        M(:,:,1:2) = repmat(tmpM(:,:,1),[1,1,2]);
                        M(:,:,3) = tmpM(:,:,2);
                    end
                else
                    M = obj.imageMatrix;
                end
                s = single(M);
            end
            
            function p = setJitter(obj, frame, time)
                persistent xy;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        if time < obj.uniqueTime*1e-3
                            xy = obj.stixelShiftPix*round((obj.stepsPerStixel-1)*(obj.positionStream.rand(1,2))) ...
                                + obj.canvasSize / 2;
                        else
                            xy = obj.stixelShiftPix*round((obj.stepsPerStixel-1)*(obj.positionStreamRep.rand(1,2))) ...
                                + obj.canvasSize / 2;
                        end
                    end
                else
                    xy = obj.canvasSize / 2;
                end
                p = xy;
            end
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current stixel size.
            obj.stixelSize = obj.stixelSizes(mod(obj.numEpochsCompleted, length(obj.stixelSizes))+1);
            obj.frameDwell = obj.frameDwells(mod(obj.numEpochsCompleted, length(obj.frameDwells))+1);
            obj.contrast_high = obj.contrastsHigh(mod(obj.numEpochsCompleted, length(obj.contrastsHigh))+1);
            obj.contrast_low = obj.contrastsLow(mod(obj.numEpochsCompleted, length(obj.contrastsLow))+1);
            
            % Deal with the seed.
            if obj.numEpochsCompleted == 0
                obj.seed = RandStream.shuffleSeed;
            else
                obj.seed = obj.seed + 1;
            end

            obj.stepsPerStixel = max(round(obj.stixelSize / obj.gridSize), 1);
            
            gridSizePix = obj.rig.getDevice('Stage').um2pix(obj.gridSize);
            %obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            obj.stixelSizePix = gridSizePix * obj.stepsPerStixel;
            obj.stixelShiftPix = obj.stixelSizePix / obj.stepsPerStixel;
            
            % Calculate the number of X/Y checks.
            obj.numXStixels = ceil(obj.canvasSize(1)/obj.stixelSizePix) + 1;
            obj.numYStixels = ceil(obj.canvasSize(2)/obj.stixelSizePix) + 1;
            obj.numXChecks = ceil(obj.canvasSize(1)/gridSizePix);
            obj.numYChecks = ceil(obj.canvasSize(2)/gridSizePix);

            % MASK REGION
            obj.mask_stream = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.contrast_mask = zeros(obj.numYStixels,obj.numXStixels,obj.num_masks);
            for jj = 1 : obj.num_masks
              mask_tmp = obj.mask_stream.rand(obj.numYStixels,obj.numXStixels)<=obj.high_fraction;
              mask_tmp = mask_tmp * (obj.contrast_high-obj.contrast_low) + obj.contrast_low;
              obj.contrast_mask(:,:,jj) = mask_tmp;
            end
            
            % Seed the generator
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.positionStream = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.noiseStreamRep = RandStream('mt19937ar', 'Seed', 1);
            obj.positionStreamRep = RandStream('mt19937ar', 'Seed', 1);
             
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('repeating_seed',1);
            epoch.addParameter('numXChecks', obj.numXChecks);
            epoch.addParameter('numYChecks', obj.numYChecks);
            epoch.addParameter('numFrames', obj.numFrames);
            epoch.addParameter('numXStixels', obj.numXStixels);
            epoch.addParameter('numYStixels', obj.numYStixels);
            epoch.addParameter('stixelSize', obj.gridSize*obj.stepsPerStixel);
            epoch.addParameter('stepsPerStixel', obj.stepsPerStixel);
            epoch.addParameter('frameDwell', obj.frameDwell);
            epoch.addParameter('contrast_high', obj.contrast_high);
            epoch.addParameter('contrast_low', obj.contrast_low);
        end
        
        function a = get.amp2(obj)
            amps = obj.rig.getDeviceNames('Amp');
            if numel(amps) < 2
                a = '(None)';
            else
                i = find(~ismember(amps, obj.amp), 1);
                a = amps{i};
            end
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.uniqueTime + obj.repeatTime;
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
        function completeRun(obj)
            completeRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            % Reset the Gamma back to the original.
            if obj.gaussianFilter
                obj.rig.getDevice('Stage').setMonitorGammaRamp(obj.monitor_gamma(1,:), obj.monitor_gamma(2,:), obj.monitor_gamma(3,:));
            end
        end
    end
end
