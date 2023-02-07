classdef FastNoise < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Noise leading duration (ms)
        stimTime = 30000                % Noise duration (ms)
        tailTime = 500                  % Noise trailing duration (ms)
        contrast = 1
        stixelSize = 60                 % Edge length of stixel (microns)
        stepsPerStixel = 2              % Size of underling grid
        gaussianFilter = true           % Whether to use a Gaussian filter
        filterSdStixels = 1.0           % Gaussian filter standard dev in stixels.
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        frameDwell = uint16(1)          % Frame dwell.
        randsPerRep = -1                % Number of random seeds between repeats
        maxWidth = 0                    % Maximum width of the stimulus in microns.
        chromaticClass = 'achromatic'   % Chromatic type
        onlineAnalysis = 'none'
        numberOfAverages = uint16(105)  % Number of epochs
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary', 'ternary', 'gaussian'})
        chromaticClassType = symphonyui.core.PropertyType('char','row',{'achromatic','RGB','BY'})
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

%             obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));

            obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            obj.stixelShiftPix = obj.stixelSizePix / obj.stepsPerStixel;
            
            if obj.maxWidth > 0
                obj.maxWidthPix = obj.rig.getDevice('Stage').um2pix(obj.maxWidth)*ones(1,2);
            else
                obj.maxWidthPix = obj.canvasSize; %min(obj.canvasSize);
            end
            
            % Calculate the number of X/Y checks.
            obj.numXStixels = ceil(obj.maxWidthPix(1)/obj.stixelSizePix) + 1;
            obj.numYStixels = ceil(obj.maxWidthPix(2)/obj.stixelSizePix) + 1;
            obj.numXChecks = ceil(obj.maxWidthPix(1)/(obj.stixelSizePix/double(obj.stepsPerStixel)));
            obj.numYChecks = ceil(obj.maxWidthPix(2)/(obj.stixelSizePix/double(obj.stepsPerStixel)));
            % Get the number of frames.
            obj.numFrames = floor(obj.stimTime * 1e-3 * obj.frameRate)+15;
            
%             if strcmp(obj.onlineAnalysis,'extracellular')
%                 obj.showFigure('manookinlab.figures.AutocorrelationFigure', obj.rig.getDevice(obj.amp));
%             end
% 
%             if ~strcmp(obj.onlineAnalysis, 'none')
%                 obj.showFigure('manookinlab.figures.JitteredNoiseFigure', ...
%                     obj.rig.getDevice(obj.amp),'recordingType', obj.onlineAnalysis,... 
%                     'stixelSize', obj.stixelSize, 'stepsPerStixel', double(obj.stepsPerStixel),...
%                     'numXChecks', obj.numXChecks, 'numYChecks', obj.numYChecks,...
%                     'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
%                     'frameRate', obj.frameRate, 'numFrames', obj.numFrames);
%             end
            
%             if ~strcmp(obj.chromaticClass,'achromatic') && isempty(strfind(obj.rig.getDevice('Stage').name, 'LightCrafter'))
%                 obj.setColorWeights();
%             end
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
                kernel = fspecial('gaussian',[3,3],obj.filterSdStixels);
%                 kernel = [0.0751    0.1238    0.0751
%                         0.1238    0.2042    0.1238
%                         0.0751    0.1238    0.0751];
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
                        M = 2*obj.backgroundIntensity * ...
                            (obj.noiseStream.rand(obj.numYStixels,obj.numXStixels)>0.5);
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
                        M = 2*obj.backgroundIntensity * ...
                            (obj.noiseStream.rand(obj.numYStixels,obj.numXStixels,3)>0.5);
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
                        tmpM = 2*obj.backgroundIntensity * ...
                            (obj.noiseStream.rand(obj.numYStixels,obj.numXStixels,2)>0.5);
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
                        xy = obj.stixelShiftPix*round((obj.stepsPerStixel-1)*(obj.positionStream.rand(1,2))) ...
                            + obj.canvasSize / 2;
                    end
                else
                    xy = obj.canvasSize / 2;
                end
                p = xy;
            end

%             function s = setStixels(obj, frame, stimFrames)
%                 if frame > 0 && frame <= stimFrames
%                     s = squeeze(obj.imageMatrix(:,:,frame));
%                 else
%                     s = squeeze(obj.imageMatrix(:,:,1));
%                 end
%             end
            
%             function s = setColorStixels(obj, frame, stimFrames)
%                 if frame > 0 && frame <= stimFrames
%                     s = squeeze(obj.imageMatrix(:,:,frame,:));
%                 else
%                     s = squeeze(obj.imageMatrix(:,:,1,:));
%                 end
%             end
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
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
            
%             obj.imageMatrix = manookinlab.util.getJitteredNoiseFrames(obj.numXStixels, obj.numYStixels, obj.numXChecks, obj.numYChecks, obj.numFrames, obj.stepsPerStixel, obj.seed, obj.frameDwell);
%             if ~strcmp(obj.chromaticClass,'achromatic') && isempty(strfind(obj.rig.getDevice('Stage').name, 'LightCrafter'))
%                 tmp = repmat(obj.imageMatrix,[1,1,1,3]);
%                 for k = 1 : 3
%                     tmp(:,:,:,k) = obj.colorWeights(k)*tmp(:,:,:,k);
%                 end
%                 
%                 switch obj.chromaticClass
%                     case 'yellow'
%                         tmp(:,:,:,3) = -1;
%                     case 'blue'
%                         tmp(:,:,:,1:2) = -1;
%                 end
%                 
%                 obj.imageMatrix = tmp;
%             end
            
%             % Multiply by the contrast and convert to uint8.
%             obj.imageMatrix = obj.contrast * obj.imageMatrix;
%             obj.imageMatrix = uint8(255*(obj.backgroundIntensity*obj.imageMatrix + obj.backgroundIntensity));
%             
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('numXChecks', obj.numXChecks);
            epoch.addParameter('numYChecks', obj.numYChecks);
            epoch.addParameter('numFrames', obj.numFrames);
            epoch.addParameter('numXStixels', obj.numXStixels);
            epoch.addParameter('numYStixels', obj.numYStixels);
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
