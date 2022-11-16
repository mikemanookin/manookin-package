classdef PinkNoise < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Noise leading duration (ms)
        stimTime = 21000                % Noise duration (ms)
        tailTime = 500                  % Noise trailing duration (ms)
        stixelSize = 30                 % Edge length of stixel (microns)
        spatialAmplitude = 1.0          % Fourier amplitude of spatial correlations (f.^-x)
        temporalAmplitude = 0.5         % Fourier amplitude of temporal correlations (f.^-x)
        rmsContrast = 0.3               % RMS contrast of stimulus
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        randsPerRep = -1                % Number of random seeds between repeats
        chromaticClass = 'achromatic'   % Chromatic type
        onlineAnalysis = 'none'
        numberOfAverages = uint16(100)    % Number of epochs
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        chromaticClassType = symphonyui.core.PropertyType('char','row',{'achromatic','RGB','BY'})
        stixelSizePix
        noiseStream
        numXChecks
        numYChecks
        seed
        frameValues
        backgroundFrame
    end
    
    methods
        function didSetRig(obj)
            didSetRig@manookinlab.protocols.ManookinLabStageProtocol(obj);

            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            end
            
            obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            
            obj.stixelSizePix

            % Calculate the number of X/Y checks.
            obj.numXChecks = ceil(obj.canvasSize(1)/obj.stixelSizePix);
            obj.numYChecks = ceil(obj.canvasSize(2)/obj.stixelSizePix);
            disp('done with prepare run')
        end

        function getFrameValues(obj, numFrames)
            if ~strcmp(obj.chromaticClass,'achromatic') && isempty(strfind(obj.rig.getDevice('Stage').name, 'LightCrafter'))
                obj.backgroundFrame = uint8(255*obj.backgroundIntensity*ones(obj.numYChecks, obj.numXChecks, 3));
            else
                obj.backgroundFrame = uint8(255*obj.backgroundIntensity*ones(obj.numYChecks, obj.numXChecks));
            end
            
            
            obj.frameValues = manookinlab.util.getPinkNoiseFrames(obj.numXChecks, obj.numYChecks, numFrames, ...
                obj.rmsContrast, obj.spatialAmplitude, obj.temporalAmplitude, obj.chromaticClass, obj.seed);
            
            % Convert to uint8 values for the display.
            obj.frameValues = obj.backgroundIntensity * obj.frameValues + obj.backgroundIntensity;
            obj.frameValues = uint8(obj.frameValues * 255);
            disp('have frame values')
        end

        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            % Create your noise image.
            imageMatrix = squeeze(obj.frameValues(:,:,1));
            checkerboard = stage.builtin.stimuli.Image(imageMatrix);
            checkerboard.position = obj.canvasSize / 2;
            checkerboard.size = [obj.numXChecks, obj.numYChecks] * obj.stixelSizePix;

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
            preF = floor(obj.preTime/1000 * 60.2);
            stimF = floor(obj.stimTime/1000 * 60.2333);

%             if ~strcmp(obj.chromaticClass,'achromatic') && isempty(strfind(obj.rig.getDevice('Stage').name, 'LightCrafter'))
%                 imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
%                     @(state)setChromaticStixels(obj, state.frame - preF, stimF));
%             else
%                 imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
%                     @(state)setAchromaticStixels(obj, state.frame - preF, stimF));
%                 imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
%                     @(state)setAchromaticStixels(obj, state.time, stimF));
%                 disp('in controller')
% %             end
%             p.addController(imgController);

            imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                @(state)setStixels(obj, state.time));
            p.addController(imgController);
            function img = setStixels(obj, time)
                img = squeeze(obj.frameValues(:,:,1));
            end
            function s = setAchromaticStixels(obj, frame, stimFrames)
                s = uint8(255*obj.backgroundIntensity*ones(obj.numXChecks, obj.numYChecks));
%                 if frame > 0 && frame <= stimFrames
%                     s = squeeze(obj.frameValues(:,:,frame));
%                 else
%                     s = obj.backgroundFrame;
%                 end
            end
            
            function s = setChromaticStixels(obj, frame, stimFrames)
                if frame > 0 && frame <= stimFrames
                    s = squeeze(obj.frameValues(:,:,frame,:));
                else
                    s = obj.backgroundFrame;
                end
            end
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the number of frames.
            numFrames = floor(obj.stimTime*1e-3 * 60.2333) + 15;
            disp('in prepare epoch')
            
            % Deal with the seed.
            if obj.randsPerRep == 0 
                obj.seed = 1;
            elseif obj.randsPerRep < 0
                if obj.numEpochsCompleted == 0
                    obj.seed = RandStream.shuffleSeed;
                else
                    obj.seed = obj.seed + 1;
                end
            elseif obj.randsPerRep > 0 && (mod(obj.numEpochsCompleted+1, obj.randsPerRep+1) == 0)
                obj.seed = 1;
            else
                if obj.numEpochsCompleted == 0
                    obj.seed = RandStream.shuffleSeed;
                else
                    obj.seed = obj.seed + 1;
                end
            end

            % Get the frame values for the epoch.
            obj.getFrameValues(numFrames);
            
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('numXChecks', obj.numXChecks);
            epoch.addParameter('numYChecks', obj.numYChecks);
            epoch.addParameter('numFrames',numFrames);
            disp('finished prepare epoch')
            size(obj.frameValues)
            size(obj.backgroundFrame)
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
