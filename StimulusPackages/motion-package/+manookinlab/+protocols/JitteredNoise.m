classdef JitteredNoise < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Noise leading duration (ms)
        stimTime = 21000                % Noise duration (ms)
        tailTime = 500                  % Noise trailing duration (ms)
        stixelSize = 80                 % Edge length of stixel (pix)
        jitterStepSize = 5              % Size of underling grid
        frameDwell = 1                  % Number of frames to display any image
        intensity = 1.0                 % Max light intensity (0-1)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        maskRadius = 0                  % Mask radius in pixels.
        apertureRadius = 0              % Aperture radius in pixels
        useRandomSeed = true            % Random seed (bool)
        onlineAnalysis = 'extracellular'
        numberOfAverages = uint16(50)    % Number of epochs
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        noiseStream
        numXChecks
        numYChecks
        correctedIntensity
        correctedMean
        seed
        backgroundFrame
        possibleShifts
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

%             obj.showFigure('manookinlab.figures.SpatialNoiseFigure', ...
%                 obj.rig.getDevice(obj.amp),'recordingType', obj.onlineAnalysis, 'stixelSize', obj.stixelSize,...
%                 'numXChecks', obj.numXChecks, 'numYChecks', obj.numYChecks,...
%                 'noiseClass', obj.noiseClass, 'chromaticClass', obj.chromaticClass,...
%                 'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
%                 'frameRate', obj.frameRate, 'numFrames', numFrames);

            % Get the frame values for repeating epochs.
            if ~obj.useRandomSeed
                obj.seed = 1;
                obj.getFrameValues();
            end
            
            % Make the background frame.
            obj.backgroundFrame = uint8(obj.correctedMean*ones(obj.numYChecks,obj.numXChecks));
            
            % Determine the number of possible shifts.
            n = floor(obj.stixelSize / obj.jitterStepSize);
            obj.possibleShifts = round((-n/2:n/2-1)*obj.jitterStepSize);
        end

 
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            % Create your noise image.
            imageMatrix = uint8((rand(obj.numYChecks, obj.numXChecks)>0.5) * obj.correctedIntensity);
            
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
            
            imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                @(state)setStixels(obj, state.time - obj.preTime * 1e-3));
            p.addController(imgController);
            
            posController = stage.builtin.controllers.PropertyController(checkerboard, 'position',...
                @(state)setPosition(obj, state.time - obj.preTime * 1e-3));
            p.addController(posController);

            function s = setStixels(obj, time)
                if time > 0
                    s = uint8(255*obj.intensity*(obj.noiseStream.rand(obj.numYChecks,obj.numXChecks)>0.5));
                else
                    s = obj.backgroundFrame;
                end
            end
            
            function p = setPosition(obj, time)
                if time > 0
                    % randomly shift
                    sh = ceil(obj.noiseStream.rand(1,2)*length(obj.possibleShifts));
                    p = obj.canvasSize / 2 + obj.possibleShifts(sh);
                else
                    p = obj.canvasSize / 2;
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

            % Deal with the seed.
            if obj.useRandomSeed
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
