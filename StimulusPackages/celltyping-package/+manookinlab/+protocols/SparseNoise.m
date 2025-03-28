classdef SparseNoise < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Noise leading duration (ms)
        stimTime = 30000                % Noise duration (ms)
        tailTime = 250                  % Noise trailing duration (ms)
        contrast = 1
        stixelSizes = [90,120]           % Edge length of stixel (microns)
        gridSize = 30                   % Size of underling grid
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        frameDwell = uint16(12)         % Frame dwell.
        pixelDensity = 0.01             % Fraction of pixels that are not gray on a frame.
        randsPerRep = -1                % Number of random seeds between repeats
        maxWidth = 0                    % Maximum width of the stimulus in microns.
        chromaticClass = 'BY'           % Chromatic type
        onlineAnalysis = 'none'
        numberOfAverages = uint16(105)  % Number of epochs
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary', 'ternary', 'gaussian'})
        chromaticClassType = symphonyui.core.PropertyType('char','row',{'achromatic','RGB','BY','S-LM'})
        stixelSizesType = symphonyui.core.PropertyType('denserealdouble','matrix')
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
        maxWidthPix
        noiseStream
        positionStream
        time_multiple
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

            if ~obj.isMeaRig
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            end
            
            try
                obj.time_multiple = obj.rig.getDevice('Stage').getExpectedRefreshRate() / obj.rig.getDevice('Stage').getMonitorRefreshRate();
%                 disp(obj.time_multiple)
            catch
                obj.time_multiple = 1.0;
            end

%             obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
%             obj.stixelShiftPix = obj.stixelSizePix / obj.stepsPerStixel;
            
            if obj.maxWidth > 0
                obj.maxWidthPix = obj.rig.getDevice('Stage').um2pix(obj.maxWidth)*ones(1,2);
            else
                obj.maxWidthPix = obj.canvasSize; %min(obj.canvasSize);
            end
            
            % Calculate the number of X/Y checks.
%             obj.numXStixels = ceil(obj.maxWidthPix(1)/obj.stixelSizePix) + 1;
%             obj.numYStixels = ceil(obj.maxWidthPix(2)/obj.stixelSizePix) + 1;
%             obj.numXChecks = ceil(obj.maxWidthPix(1)/(obj.stixelSizePix/double(obj.stepsPerStixel)));
%             obj.numYChecks = ceil(obj.maxWidthPix(2)/(obj.stixelSizePix/double(obj.stepsPerStixel)));
            % Get the number of frames.
            obj.numFrames = floor(obj.stimTime * 1e-3 * obj.frameRate)+15;
            
            if strcmp(obj.chromaticClass,'S-LM')
            end
        end

 
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3 * obj.time_multiple);
            p.setBackgroundColor(obj.backgroundIntensity);

            obj.imageMatrix = obj.backgroundIntensity * ones(obj.numYStixels,obj.numXStixels);
            checkerboard = stage.builtin.stimuli.Image(uint8(obj.imageMatrix));
            checkerboard.position = obj.canvasSize / 2;
            checkerboard.size = [obj.numXStixels, obj.numYStixels] * obj.stixelSizePix;

            % Set the minifying and magnifying functions to form discrete
            % stixels.
            checkerboard.setMinFunction(GL.NEAREST);
            checkerboard.setMagFunction(GL.NEAREST);
            
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
                        @(state)setBYStixels(obj, state.frame - preF));
                else
                    imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                        @(state)setRGBStixels(obj, state.frame - preF));
                end
            else
                imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                    @(state)setStixels(obj, state.frame - preF));
%                 imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
%                     @(state)setStixels(obj, state.frame - preF, stimF));
            end
            p.addController(imgController);
            
            % Position controller
            if obj.stepsPerStixel > 1
                xyController = stage.builtin.controllers.PropertyController(checkerboard, 'position',...
                    @(state)setJitter(obj, state.frame - preF));
                p.addController(xyController);
            end
            
            function s = setStixels(obj, frame)
                persistent M;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        M = obj.noiseStream.rand(obj.numYStixels,obj.numXStixels);
                        M(M < 1-obj.pixelDensity/2 & (M > obj.pixelDensity/2)) = 0.5;
                        M(M > 0.5) = 1;
                        M(M < 0.5) = 0;
                        M = 2*obj.backgroundIntensity * M;
                    end
                else
                    M = obj.imageMatrix;
                end
                s = uint8(255*M);
            end
            
            % RGB noise
            function s = setRGBStixels(obj, frame)
                persistent M;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        M = obj.noiseStream.rand(obj.numYStixels,obj.numXStixels,3);
                        M(M < 1-obj.pixelDensity/2 & (M > obj.pixelDensity/2)) = 0.5;
                        M(M > 0.5) = 1;
                        M(M < 0.5) = 0;
                        M = 2*obj.backgroundIntensity * M;
                    end
                else
                    M = obj.imageMatrix;
                end
                s = uint8(255*M);
            end
            
            % Blue-Yellow noise
            function s = setBYStixels(obj, frame)
                persistent M;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        M = zeros(obj.numYStixels,obj.numXStixels,3);
                        tmpM = obj.noiseStream.rand(obj.numYStixels,obj.numXStixels,2);
                        tmpM(tmpM < 1-obj.pixelDensity/2 & (tmpM > obj.pixelDensity/2)) = 0.5;
                        tmpM(tmpM > 0.5) = 1;
                        tmpM(tmpM < 0.5) = 0;
                        tmpM = 2*obj.backgroundIntensity * tmpM;
                        M(:,:,1:2) = repmat(tmpM(:,:,1),[1,1,2]);
                        M(:,:,3) = tmpM(:,:,2);
                    end
                else
                    M = obj.imageMatrix;
                end
                s = uint8(255*M);
            end
            
            function p = setJitter(obj, frame)
                persistent xy;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        xy = round(obj.stixelShiftPix*(obj.stepsPerStixel-1)*(obj.positionStream.rand(1,2)>0.5)) ...
                            + obj.canvasSize / 2;
                    end
                else
                    xy = obj.canvasSize / 2;
                end
                p = xy;
            end
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Remove the Amp responses if it's an MEA rig.
            if obj.isMeaRig
                amps = obj.rig.getDevices('Amp');
                for ii = 1:numel(amps)
                    if epoch.hasResponse(amps{ii})
                        epoch.removeResponse(amps{ii});
                    end
                    if epoch.hasStimulus(amps{ii})
                        epoch.removeStimulus(amps{ii});
                    end
                end
            end
            
            % Get the current stixel size.
            obj.stixelSize = obj.stixelSizes(mod(obj.numEpochsCompleted, length(obj.stixelSizes))+1);
            
            obj.stepsPerStixel = max(round(obj.stixelSize / obj.gridSize), 1);
            
            gridSizePix = obj.rig.getDevice('Stage').um2pix(obj.gridSize);
            %obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            obj.stixelSizePix = gridSizePix * obj.stepsPerStixel;
            obj.stixelShiftPix = obj.stixelSizePix / obj.stepsPerStixel;
            
            % Calculate the number of X/Y checks.
            obj.numXStixels = ceil(obj.maxWidthPix(1)/obj.stixelSizePix) + 1;
            obj.numYStixels = ceil(obj.maxWidthPix(2)/obj.stixelSizePix) + 1;
            obj.numXChecks = ceil(obj.maxWidthPix(1)/gridSizePix);
            obj.numYChecks = ceil(obj.maxWidthPix(2)/gridSizePix);
            
            % Deal with the seed.
            if obj.randsPerRep == 0 
                obj.seed = 1;
            elseif obj.randsPerRep < 0
                if obj.numEpochsCompleted == 0
                    obj.seed = RandStream.shuffleSeed;
                else
                    obj.seed = obj.seed + 1;
                end
            elseif obj.randsPerRep > 0 && (mod(obj.numEpochsCompleted+1,obj.randsPerRep+1) == 0)
                obj.seed = 1;
            else
                if obj.numEpochsCompleted == 0
                    obj.seed = RandStream.shuffleSeed;
                else
                    obj.seed = obj.seed + 1;
                end
            end
            
            % Seed the generator
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.positionStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('numXChecks', obj.numXChecks);
            epoch.addParameter('numYChecks', obj.numYChecks);
            epoch.addParameter('numFrames', obj.numFrames);
            epoch.addParameter('numXStixels', obj.numXStixels);
            epoch.addParameter('numYStixels', obj.numYStixels);
            
            epoch.addParameter('stixelSize', obj.gridSize*obj.stepsPerStixel);
            epoch.addParameter('stepsPerStixel', obj.stepsPerStixel);
        end
        
        function deltaRGB = getDeltaRGB(obj, gunMeans, isoM)
            deltaRGB = 2*(obj.quantalCatch(:,1:3).*(ones(3,1)*gunMeans(:)')')' \ isoM;
            deltaRGB = deltaRGB / max(abs(deltaRGB));
        end

        function cWeber = getConeContrasts(obj, gunMeans, deltaRGB)
            meanFlux = (gunMeans(:)*ones(1,3)) .* obj.quantalCatch(:,1:3);

            iDelta = sum((deltaRGB(:)*ones(1,3)) .* meanFlux);
            % Calculate the max contrast of each cone type. (Weber contrast)
            cWeber = iDelta ./ sum(meanFlux,1);
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

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
