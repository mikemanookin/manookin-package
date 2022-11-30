classdef PinkNoise < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Noise leading duration (ms)
        stimTime = 21000                % Noise duration (ms)
        tailTime = 250                  % Noise trailing duration (ms)
        stixelSize = 30                 % Edge length of stixel (microns)
        rmsContrast = 0.35              % RMS contrast
        spatialAmplitude = 1.0          % Amplitude of spatial correlations
        temporalAmplitude = 0.25        % Amplitude of temporal correlations
        preGenerateFrames = false       % Boolean (pre-generate frames?)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        randsPerRep = -1                % Number of random seeds between repeats
        chromaticClass = 'BY'           % Chromatic type
        onlineAnalysis = 'none'
        numberOfAverages = uint16(105)  % Number of epochs
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        chromaticClassType = symphonyui.core.PropertyType('char','row',{'achromatic','BY','RGB'})
        numXChecks
        numYChecks
        seed
        numFrames
        stixelSizePix
        imageMatrix
        frameBuffer
        noiseStream
        space_filter
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

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));

            obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            
            % Calculate the number of X/Y checks.
            obj.numXChecks = ceil(obj.canvasSize(1)/obj.stixelSizePix);
            obj.numYChecks = ceil(obj.canvasSize(2)/obj.stixelSizePix);
            % Get the number of frames.
            obj.numFrames = floor(obj.stimTime * 1e-3 * 60.319152);
            
            if strcmp(obj.onlineAnalysis,'extracellular')
                obj.showFigure('manookinlab.figures.AutocorrelationFigure', obj.rig.getDevice(obj.amp));
            end
            
            if ~obj.preGenerateFrames
                obj.frameBuffer = [];
            end
            
            if ~strcmp(obj.chromaticClass,'achromatic') && isempty(strfind(obj.rig.getDevice('Stage').name, 'LightCrafter'))
                obj.setColorWeights();
            end
        end
        
        function get_spatial_filter(obj)
            x = [(0:floor(obj.numXChecks/2)) -(ceil(obj.numXChecks/2)-1:-1:1)]'/obj.numXChecks;
            x = abs(x);
            % Reproduce these frequencies along ever row
            x = repmat(x,1,obj.numYChecks);
            % v is the set of frequencies along the second dimension.  For a square
            % region it will be the transpose of u
            y = [(0:floor(obj.numYChecks/2)) -(ceil(obj.numYChecks/2)-1:-1:1)]/obj.numXChecks;
            y = abs(y);
            % Reproduce these frequencies along ever column
            y = repmat(y,obj.numXChecks,1);
            obj.space_filter = (x.^2 + y.^2) .^ -(obj.spatialAmplitude/2);
            obj.space_filter = obj.space_filter';
            obj.space_filter(obj.space_filter == inf) = 0;
        end

 
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            checkerboard = stage.builtin.stimuli.Image(obj.imageMatrix(:,:,1));
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
            preF = floor(obj.preTime/1000 * obj.frameRate);
            stimF = obj.numFrames;

            if ~strcmp(obj.chromaticClass,'achromatic') && isempty(strfind(obj.rig.getDevice('Stage').name, 'LightCrafter'))
                imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                    @(state)setColorStixels(obj, state.frame - preF, stimF));
            else
                imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                    @(state)setStixels(obj, state.frame - preF, stimF));
            end
            p.addController(imgController);

            function s = setStixels(obj, frame, stimFrames)
                if frame > 0 && frame <= stimFrames
                    s = squeeze(obj.imageMatrix(:,:,frame));
                else
                    s = squeeze(obj.imageMatrix(:,:,1));
                end
            end
            
            function s = setColorStixels(obj, frame, stimFrames)
                if frame > 0 && frame <= stimFrames
                    s = squeeze(obj.imageMatrix(:,:,frame,:));
                else
                    s = squeeze(obj.imageMatrix(:,:,1,:));
                end
            end
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
            
%             obj.imageMatrix = manookinlab.util.getJitteredNoiseFrames(obj.numXStixels, obj.numYStixels, obj.numXChecks, obj.numYChecks, obj.numFrames, obj.stepsPerStixel, obj.seed, obj.frameDwell);
            obj.imageMatrix = manookinlab.util.getPinkNoiseFrames(obj.numXChecks, obj.numYChecks, obj.numFrames, ...
                obj.rmsContrast, obj.spatialAmplitude, obj.temporalAmplitude, obj.chromaticClass, obj.seed);
            
            % Multiply by the contrast and convert to uint8.
            obj.imageMatrix = uint8(255*(obj.backgroundIntensity*obj.imageMatrix + obj.backgroundIntensity));
            
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('numXChecks', obj.numXChecks);
            epoch.addParameter('numYChecks', obj.numYChecks);
            epoch.addParameter('numFrames', obj.numFrames);
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
