classdef PinkNoise < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Noise leading duration (ms)
        stimTime = 21000                % Noise duration (ms)
        tailTime = 500                  % Noise trailing duration (ms)
        stixelSize = 25                 % Edge length of stixel (pix)
        frameDwell = 1                  % Number of frames to display any image
        intensity = 1.0                 % Max light intensity (0-1)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        maskRadius = 0                  % Mask radius in pixels.
        apertureRadius = 0              % Aperture radius in pixels
        useRandomSeed = true            % Random seed (bool)
        noiseClass = 'binary'           % Noise class (binary or Gaussian)
        chromaticClass = 'achromatic'  % Chromatic type
        onlineAnalysis = 'none'
        numberOfAverages = uint16(50)    % Number of epochs
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary', 'ternary', 'gaussian'})
        chromaticClassType = symphonyui.core.PropertyType('char','row',{'achromatic','RGB','L-iso','M-iso','S-iso'})
        noiseStream
        numXChecks
        numYChecks
        correctedIntensity
        correctedMean
        seed
        frameValues
        backgroundFrame
        strf
        spatialRF
    end

    properties (Hidden, Transient)
        analysisFigure
    end

    methods
        function didSetRig(obj)
            didSetRig@manookinlab.protocols.ManookinLabStageProtocol(obj);

            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));

            % Get the frame rate. Need to check if it's a LCR rig.
            if ~isempty(strfind(obj.rig.getDevice('Stage').name, 'LightCrafter'))
                obj.chromaticClass = 'achromatic';
            end

            % Calculate the corrected intensity.
            obj.correctedIntensity = obj.intensity * 255;
            obj.correctedMean = obj.backgroundIntensity * 255;

            % Calculate the number of X/Y checks.
            obj.numXChecks = ceil(obj.canvasSize(1)/obj.stixelSize);
            obj.numYChecks = ceil(obj.canvasSize(2)/obj.stixelSize);
            numFrames = floor(obj.stimTime/1000 * obj.frameRate / obj.frameDwell);

            obj.showFigure('manookinlab.figures.SpatialNoiseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType', obj.onlineAnalysis, 'stixelSize', obj.stixelSize,...
                'numXChecks', obj.numXChecks, 'numYChecks', obj.numYChecks,...
                'noiseClass', obj.noiseClass, 'chromaticClass', obj.chromaticClass,...
                'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                'frameRate', obj.frameRate, 'numFrames', numFrames);

            % Automated analysis figure.
%             if ~strcmp(obj.onlineAnalysis,'none')
%                 % custom figure handler
%                 if isempty(obj.analysisFigure) || ~isvalid(obj.analysisFigure)
%                     obj.analysisFigure = obj.showFigure('symphonyui.builtin.figures.CustomFigure', @obj.getSTRF);
%                     f = obj.analysisFigure.getFigureHandle();
%                     set(f, 'Name', 'spatial receptive field');
%                     obj.analysisFigure.userData.axesHandle = axes('Parent', f);
%                 end
%
%                 % Init the strf.
%                 if strcmp(obj.chromaticClass, 'achromatic')
%                     obj.strf = zeros(obj.numYChecks, obj.numXChecks, floor(obj.frameRate*0.5/obj.frameDwell));
%                     obj.spatialRF = zeros(obj.numYChecks, obj.numXChecks);
%                 else
%                     obj.strf = zeros(3, obj.numYChecks, obj.numXChecks, floor(obj.frameRate*0.5/obj.frameDwell));
%                     obj.spatialRF = zeros(obj.numYChecks, obj.numXChecks, 3);
%                 end
%             end

            % Get the frame values for repeating epochs.
            if ~obj.useRandomSeed
                obj.seed = 1;
                obj.getFrameValues();
            end

            obj.setColorWeights();
        end

        function getFrameValues(obj)
            % Get the number of frames.
            numFrames = floor(obj.stimTime/1000 * obj.frameRate / obj.frameDwell);

            % Seed the random number generator.
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);

            % Deal with the noise type.
            if strcmpi(obj.noiseClass, 'binary')
                if strcmpi(obj.chromaticClass, 'RGB')
                    M = obj.noiseStream.rand(numFrames,obj.numYChecks,obj.numXChecks,3) > 0.5;
                    obj.backgroundFrame = uint8(obj.backgroundIntensity*ones(obj.numYChecks,obj.numXChecks,3));
                elseif strcmpi(obj.chromaticClass, 'achromatic')
                    M = obj.noiseStream.rand(numFrames, obj.numYChecks,obj.numXChecks) > 0.5;
                    obj.backgroundFrame = uint8(obj.backgroundIntensity*ones(obj.numYChecks,obj.numXChecks));
                else
                    tmp = repmat(obj.noiseStream.rand(numFrames, obj.numYChecks, obj.numXChecks) > 0.5,[1 1 1 3]);
                    M = zeros(size(tmp));
                    tmp = 2*tmp-1; % Convert to contrast.
                    for k = 1 : 3
                        M(:,:,:,k) = obj.colorWeights(k)*tmp(:,:,:,1);
                    end
                    M = 0.5*M+0.5;
                    obj.backgroundFrame = uint8(obj.backgroundIntensity*ones(obj.numYChecks,obj.numXChecks,3));
                end
                obj.frameValues = uint8(obj.intensity*255*M);
            elseif strcmpi(obj.noiseClass, 'ternary')

                if strcmpi(obj.chromaticClass, 'RGB')
                    eta = double(obj.noiseStream.randn(numFrames,obj.numYChecks, obj.numXChecks,3) > 0)*2 - 1;
                    M = (eta + circshift(eta, [0, 1, 1])) / 2;
                    M = 0.5*M+0.5;
                    obj.backgroundFrame = uint8(obj.backgroundIntensity*ones(obj.numYChecks,obj.numXChecks,3));
                elseif strcmpi(obj.chromaticClass, 'achromatic')
                    eta = double(obj.noiseStream.randn(numFrames,obj.numYChecks, obj.numXChecks) > 0)*2 - 1;
                    M = (eta + circshift(eta, [0, 1, 1])) / 2;
                    M = 0.5*M+0.5;
                    obj.backgroundFrame = uint8(obj.backgroundIntensity*ones(obj.numYChecks,obj.numXChecks));
                else
                    eta = double(obj.noiseStream.randn(numFrames,obj.numYChecks, obj.numXChecks) > 0)*2 - 1;
                    tmp = repmat((eta + circshift(eta, [0, 1, 1])) / 2,[1 1 1 3]);
                    M = zeros(size(tmp));
                    for k = 1 : 3
                        M(:,:,:,k) = obj.colorWeights(k)*tmp(:,:,:,1);
                    end
                    M = obj.backgroundIntensity*M+obj.backgroundIntensity;
                    obj.backgroundFrame = uint8(obj.backgroundIntensity*ones(obj.numYChecks,obj.numXChecks,3));
                end

                obj.frameValues = uint8(obj.intensity*255*M);
            else
                if strcmpi(obj.chromaticClass, 'RGB')
                    M = uint8((0.3*obj.intensity*obj.noiseStream.rand(numFrames, obj.numYChecks, obj.numXChecks, 3) * 0.5 + 0.5)*255);
                    obj.backgroundFrame = uint8(obj.backgroundIntensity*ones(obj.numYChecks,obj.numXChecks,3));
                elseif strcmpi(obj.chromaticClass, 'achromatic')
                    M = uint8((0.3*obj.intensity*obj.noiseStream.rand(numFrames, obj.numYChecks, obj.numXChecks) * 0.5 + 0.5)*255);
                    obj.backgroundFrame = uint8(obj.backgroundIntensity*ones(obj.numYChecks,obj.numXChecks));
                else
                    tmp = repmat(0.3*obj.noiseStream.randn(numFrames, obj.numYChecks, obj.numXChecks),[1 1 1 3]);
                    M = zeros(size(tmp));
                    for k = 1 : 3
                        M(:,:,:,k) = obj.colorWeights(k)*tmp;
                    end
                    M = uint8(255*(0.5*M+0.5));
                    obj.backgroundFrame = uint8(obj.backgroundIntensity*ones(obj.numYChecks,obj.numXChecks,3));
                end
                obj.frameValues = M;
            end
        end

        % Online analysis function.
        function getSTRF(obj, ~, epoch)
            response = epoch.getResponse(obj.rig.getDevice(obj.amp));
            responseTrace = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;

            % Analyze response by type.
            responseTrace = obj.getResponseByType(responseTrace, obj.onlineAnalysis);

            responseTrace = responseTrace(obj.preTime/1000*sampleRate+1 : end);
            binWidth = sampleRate / obj.frameRate * obj.frameDwell;
            numBins = floor(obj.stimTime/1000 * obj.frameRate / obj.frameDwell);
            binData = zeros(1, numBins);
            for k = 1 : numBins
                index = round((k-1)*binWidth+1 : k*binWidth);
                binData(k) = mean(responseTrace(index));
            end

            % Regenerate the stimulus based on the type.
            stimulus = 2*(double(obj.frameValues)/255)-1;

            filterFrames = floor(obj.frameRate*0.5/obj.frameDwell);
            lobePts = round(0.05*filterFrames/0.5) : round(0.15*filterFrames/0.5);

            % Do the reverse correlation.
            if strcmp(obj.chromaticClass, 'achromatic')
                filterTmp = zeros(obj.numYChecks,obj.numXChecks,filterFrames);
                for m = 1 : obj.numYChecks
                    for n = 1 : obj.numXChecks
                        tmp = ifft(fft(binData') .* conj(fft(squeeze(stimulus(:,m,n)))));
                        filterTmp(m,n,:) = tmp(1 : filterFrames);
                    end
                end
                obj.strf = obj.strf + filterTmp;
                obj.spatialRF = squeeze(mean(obj.strf(:,:,lobePts),3));
            else

                for l = 1 : 3
                    filterTmp = zeros(obj.numYChecks,obj.numXChecks,filterFrames);
                    for m = 1 : obj.numYChecks
                        for n = 1 : obj.numXChecks
                            tmp = ifft(fft(binData') .* conj(fft(squeeze(stimulus(:,m,n,l)))));
                            filterTmp(m,n,:) = tmp(1 : filterFrames);
                        end
                    end
                    obj.strf(l,:,:,:) = squeeze(obj.strf(l,:,:,:)) + filterTmp;
                    obj.spatialRF(:,:,l) = squeeze(mean(obj.strf(l,:,:,lobePts),4));
                end

            end

            axesHandle = obj.analysisFigure.userData.axesHandle;
            cla(axesHandle);

            h1 = axesHandle;
            imagesc(h1,obj.spatialRF);
%             axis(h1, 'image');
            set(h1, 'TickDir', 'out');
            title(['Epoch ', num2str(obj.numEpochsCompleted), ' of ', num2str(obj.numberOfAverages)], 'Parent', h1);
        end

        function flipDurations = getFlips(obj)
            info = obj.rig.getDevice('Stage').getPlayInfo();
            %software timing
            flipDurations = info.flipDurations;
        end

        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            % Create your noise image.
            if strcmpi(obj.noiseClass, 'binary')
                imageMatrix = uint8((rand(obj.numYChecks, obj.numXChecks)>0.5) * obj.correctedIntensity);
            else
                imageMatrix = uint8((0.3*randn(obj.numYChecks, obj.numXChecks) * obj.backgroundIntensity + obj.backgroundIntensity)*255);
            end
            checkerboard = stage.builtin.stimuli.Image(imageMatrix);
            checkerboard.position = obj.canvasSize / 2;
            checkerboard.size = [obj.numXChecks obj.numYChecks] * obj.stixelSize;

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
            preF = floor(obj.preTime/1000 * obj.frameRate);
            stimF = floor(obj.stimTime/1000 * obj.frameRate);

            if strcmpi(obj.chromaticClass, 'achromatic')
                imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                    @(state)setAchromaticStixels(obj, state.frame - preF, stimF));
            else
                imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                    @(state)setChromaticStixels(obj, state.frame - preF, stimF));
            end
            p.addController(imgController);

            function s = setAchromaticStixels(obj, frame, stimFrames)
                if frame > 0 && frame <= stimFrames
                    index = ceil(frame/obj.frameDwell);
                    s = squeeze(obj.frameValues(index,:,:));
                else
                    s = obj.backgroundFrame;
                end
            end

            function s = setChromaticStixels(obj, frame, stimFrames)
                if frame > 0 && frame <= stimFrames
                    index = ceil(frame/obj.frameDwell);
                    s = squeeze(obj.frameValues(index,:,:,:));
                else
                    s = obj.backgroundFrame;
                end
            end

            % Deal with the mask, if necessary.
            if obj.maskRadius > 0
                mask = stage.builtin.stimuli.Ellipse();
                mask.color = obj.backgroundIntensity;
                mask.radiusX = obj.maskRadius;
                mask.radiusY = obj.maskRadius;
                mask.position = obj.canvasSize / 2 + obj.centerOffset;
                p.addStimulus(mask);
            end

            if obj.apertureRadius > 0
              aperture = stage.builtin.stimuli.Rectangle();
              aperture.position = obj.canvasSize/2 + obj.centerOffset;
              aperture.color = obj.backgroundIntensity;
              aperture.size = [max(obj.canvasSize) max(obj.canvasSize)];
              mask = stage.core.Mask.createCircularAperture(obj.apertureRadius*2/max(obj.canvasSize), 1024);
              aperture.setMask(mask);
              p.addStimulus(aperture);
            end
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);

%             device = obj.rig.getDevice(obj.amp);
%             duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
%             epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
%             epoch.addResponse(device);

            % Deal with the seed.
            if obj.useRandomSeed
                obj.seed = RandStream.shuffleSeed;
                % Get the frame values for the epoch.
                obj.getFrameValues();
            end
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('numXChecks', obj.numXChecks);
            epoch.addParameter('numYChecks', obj.numYChecks);
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end