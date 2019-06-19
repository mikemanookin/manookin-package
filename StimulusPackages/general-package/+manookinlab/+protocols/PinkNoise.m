classdef PinkNoise < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Noise leading duration (ms)
        stimTime = 21000                % Noise duration (ms)
        tailTime = 500                  % Noise trailing duration (ms)
        stixelSize = 25                 % Edge length of stixel (pix)
        rmsContrast = 0.3               % RMS contrast of stimulus
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        maskRadius = 0                  % Mask radius in pixels.
        apertureRadius = 0              % Aperture radius in pixels
        useRandomSeed = true            % Random seed (bool)
        spatialCorrelations = 'f^-1'    % Power of spatial correlations
        temporalCorrelations = 'f^-1'   % Power of temporal correlations
        onlineAnalysis = 'extracellular'
        numberOfAverages = uint16(100)    % Number of epochs
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        chromaticClassType = symphonyui.core.PropertyType('char','row',{'achromatic','RGB','L-iso','M-iso','S-iso'})
        spatialCorrelationsType = symphonyui.core.PropertyType('char', 'row', {'f^-1', 'f^-0.5', 'f^-2'})
        temporalCorrelationsType = symphonyui.core.PropertyType('char', 'row', {'f^-1', 'f^-0.5', 'f^-0.25'})
        noiseStream
        numXChecks
        numYChecks
        seed
        frameValues
        backgroundFrame
        strf
        spatialRF
        spatialPower
        temporalPower
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

            % Calculate the number of X/Y checks.
            obj.numXChecks = ceil(obj.canvasSize(1)/obj.stixelSize);
            obj.numYChecks = ceil(obj.canvasSize(2)/obj.stixelSize);
            numFrames = floor(obj.stimTime * 1e-3 * obj.frameRate);
            
            switch obj.spatialCorrelations
                case 'f^-1'
                    obj.spatialPower = 1;
                case 'f^-0.5'
                    obj.spatialPower = 0.5;
                case 'f^-2'
                    obj.spatialPower = 2;
            end
            
            switch obj.spatialCorrelations
                case 'f^-1'
                    obj.temporalPower = 1;
                case 'f^-0.5'
                    obj.temporalPower = 0.5;
                case 'f^-0.25'
                    obj.temporalPower = 0.25;
            end

            obj.showFigure('manookinlab.figures.SpatialNoiseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType', obj.onlineAnalysis, 'stixelSize', obj.stixelSize,...
                'numXChecks', obj.numXChecks, 'numYChecks', obj.numYChecks,...
                'noiseClass', 'pink', 'chromaticClass', 'achromatic',...
                'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                'frameRate', obj.frameRate, 'numFrames', numFrames);

            % Get the frame values for repeating epochs.
            if ~obj.useRandomSeed
                obj.seed = 1;
                obj.getFrameValues();
            end
        end

        function getFrameValues(obj)
            % Get the number of frames.
            numFrames = floor(obj.stimTime*1e-3 * obj.frameRate) + 15;

            obj.backgroundFrame = uint8(obj.backgroundIntensity*ones(obj.numYChecks, obj.numXChecks));
            
            obj.frameValues = manookinlab.util.getPinkNoiseFrames(obj.numXChecks, obj.numYChecks, numFrames, ...
                obj.rmsContrast, obj.spatialPower, obj.temporalPower, obj.seed);
            
            % Convert to uint8 values for the display.
            obj.frameValues = obj.backgroundIntensity * obj.frameValues + obj.backgroundIntensity;
            obj.frameValues = uint8(obj.frameValues * 255);
        end

        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            % Create your noise image.
            imageMatrix = uint8((0.3*randn(obj.numYChecks, obj.numXChecks) * obj.backgroundIntensity + obj.backgroundIntensity)*255);
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

            imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                @(state)setAchromaticStixels(obj, state.frame - preF, stimF));
            p.addController(imgController);

            function s = setAchromaticStixels(obj, frame, stimFrames)
                if frame > 0 && frame <= stimFrames
                    s = squeeze(obj.frameValues(frame,:,:));
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
                mask.position = obj.canvasSize / 2;
                p.addStimulus(mask);
            end

            if obj.apertureRadius > 0
              aperture = stage.builtin.stimuli.Rectangle();
              aperture.position = obj.canvasSize/2;
              aperture.color = obj.backgroundIntensity;
              aperture.size = [max(obj.canvasSize) max(obj.canvasSize)];
              mask = stage.core.Mask.createCircularAperture(obj.apertureRadius*2/max(obj.canvasSize), 1024);
              aperture.setMask(mask);
              p.addStimulus(aperture);
            end
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);

            % Deal with the seed.
            if obj.useRandomSeed
                obj.seed = RandStream.shuffleSeed;
                % Get the frame values for the epoch.
                obj.getFrameValues();
            end
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('numXChecks', obj.numXChecks);
            epoch.addParameter('numYChecks', obj.numYChecks);
            epoch.addParameter('spatialPower',obj.spatialPower);
            epoch.addParameter('temporalPower',obj.temporalPower);
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
