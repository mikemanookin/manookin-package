classdef SpatialNoise2 < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Noise leading duration (ms)
        stimTime = 20000                % Noise duration (ms)
        tailTime = 250                  % Noise trailing duration (ms)
        stixelSize = 25                 % Edge length of stixel (microns)
        frameDwell = 1                  % Number of frames to display any image
        noiseContrast = 1.0             % Max light intensity (0-1)
        dimensionality = '1-d'          % Stixel dimensionality
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        maskRadius = 0                  % Mask radius in microns.
        apertureRadius = 0              % Aperture radius in microns
        randsPerRep = 8                 % Number of random seeds per repeat
        noiseClass = 'binary'           % Noise class (binary or Gaussian)
        onlineAnalysis = 'extracellular'
        numberOfAverages = uint16(100)    % Number of epochs
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary', 'ternary', 'gaussian'})
        dimensionalityType = symphonyui.core.PropertyType('char', 'row', {'1-d', '2-d'});
        noiseStream
        numXChecks
        numYChecks
        correctedIntensity
        correctedMean
        seed
        frameValues
        backgroundFrame
        stixelSizePix
        maskRadiusPix
        apertureRadiusPix
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
            
            obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            obj.maskRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.maskRadius);
            obj.apertureRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.apertureRadius);

            % Calculate the corrected intensity.
            obj.correctedIntensity = obj.intensity * 255;
            obj.correctedMean = obj.backgroundIntensity * 255;
            
            
            % Calculate the X/Y stixels.
            obj.numYChecks = ceil(sz(2)/obj.stixelSizePix);
            if strcmpi(obj.dimensionality, '1-d')
                obj.numXChecks = 1;
                obj.stixelDims = [obj.canvasSize(1) obj.stixelSizePix];
            else
                obj.numXChecks = ceil(obj.canvasSize(1)/obj.stixelSizePix);
                obj.stixelDims = obj.stixelSizePix*ones(1,2);
            end

            % Calculate the number of X/Y checks.
            
            obj.numYChecks = ceil(obj.canvasSize(2)/obj.stixelSizePix);
            numFrames = floor(obj.stimTime/1000 * obj.frameRate / obj.frameDwell);

            obj.showFigure('manookinlab.figures.SpatialNoiseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType', obj.onlineAnalysis, 'stixelSize', obj.stixelSize,...
                'numXChecks', obj.numXChecks, 'numYChecks', obj.numYChecks,...
                'noiseClass', obj.noiseClass, 'chromaticClass', obj.chromaticClass,...
                'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                'frameRate', obj.frameRate, 'numFrames', numFrames);
            
            % Get the background gray frame
            obj.backgroundFrame = uint8(obj.backgroundIntensity*ones(obj.numYChecks,obj.numXChecks));
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
            checkerboard.size = [obj.numXChecks obj.numYChecks] .* obj.stixelDims;

            % Set the minifying and magnifying functions to form discrete
            % stixels.
            checkerboard.setMinFunction(GL.NEAREST);
            checkerboard.setMagFunction(GL.NEAREST);

            % Add the stimulus to the presentation.
            p.addStimulus(checkerboard);

            gridVisible = stage.builtin.controllers.PropertyController(checkerboard, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(gridVisible);

            if strcmpi(obj.noiseClass, 'binary')
                imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                    @(state)getStixelsBinary(obj, state.time - obj.preTime * 1e-3));
            else
                imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                    @(state)getStixelsGaussian(obj, state.frame - preF, stimF));
            end
            p.addController(imgController);


            function c = getStixelsGaussian(obj, time)
                if time > 0 && time <= obj.stimTime*1e-3
                    c = (obj.noiseContrast * (0.3*obj.noiseStream.randn(obj.numYChecks,obj.numXChecks))) * obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    c = obj.backgroundIntensity;
                end
            end
            
            function c = getStixelsBinary(obj, time)
                if time > 0 && time <= obj.stimTime*1e-3
                    c = (obj.noiseContrast * (2*(obj.noiseStream.rand(obj.numYChecks,obj.numXChecks)>0.5)-1)) * obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    c = obj.backgroundIntensity;
                end
            end

            % Deal with the mask, if necessary.
            if obj.maskRadiusPix > 0
                mask = stage.builtin.stimuli.Ellipse();
                mask.color = obj.backgroundIntensity;
                mask.radiusX = obj.maskRadiusPix;
                mask.radiusY = obj.maskRadiusPix;
                mask.position = obj.canvasSize / 2;
                p.addStimulus(mask);
            end

            if obj.apertureRadiusPix > 0
              aperture = stage.builtin.stimuli.Rectangle();
              aperture.position = obj.canvasSize/2;
              aperture.color = obj.backgroundIntensity;
              aperture.size = [max(obj.canvasSize) max(obj.canvasSize)];
              mask = stage.core.Mask.createCircularAperture(obj.apertureRadiusPix*2/max(obj.canvasSize), 1024);
              aperture.setMask(mask);
              p.addStimulus(aperture);
            end
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);

            % Deal with the seed.
            if obj.randsPerRep <= 0
                obj.seed = 1;
            elseif obj.randsPerRep > 0 && (mod(obj.numEpochsCompleted+1,obj.randsPerRep+1) == 0)
                obj.seed = 1;
            else
                obj.seed = RandStream.shuffleSeed;
            end
            
            % Seed the random number generator.
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
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
