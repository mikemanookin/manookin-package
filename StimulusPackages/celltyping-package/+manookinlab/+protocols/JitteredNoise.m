classdef JitteredNoise < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Noise leading duration (ms)
        stimTime = 21000                % Noise duration (ms)
        tailTime = 500                  % Noise trailing duration (ms)
        stixelSize = 40                 % Edge length of stixel (microns)
        stepsPerStixel = 2              % Size of underling grid
        contrast = 1.0                  % Max light contrast (0-1)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        randsPerRep = -1                % Number of random seeds between repeats
        maxWidth = 0                    % Maximum width of the stimulus in microns.
        onlineAnalysis = 'extracellular'
        numberOfAverages = uint16(105)  % Number of epochs
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        numXStixels
        numYStixels
        numXChecks
        numYChecks
        seed
        numFrames
        stixelSizePix
        imageMatrix
        maxWidthPix
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
            
            if obj.maxWidth > 0
                obj.maxWidthPix = obj.rig.getDevice('Stage').um2pix(obj.maxWidth);
            else
                obj.maxWidthPix = min(obj.canvasSize);
            end
            
            % Calculate the number of X/Y checks.
            obj.numXStixels = ceil(obj.maxWidthPix/obj.stixelSizePix) + 1;
            obj.numYStixels = ceil(obj.maxWidthPix/obj.stixelSizePix) + 1;
            obj.numXChecks = ceil((obj.numXStixels-1) * double(obj.stepsPerStixel));
            obj.numYChecks = ceil((obj.numYStixels-1) * double(obj.stepsPerStixel));
            % Get the number of frames.
            obj.numFrames = floor(obj.stimTime * 1e-3 * obj.frameRate)+15;
            
            if strcmp(obj.onlineAnalysis,'extracellular')
                obj.showFigure('manookinlab.figures.AutocorrelationFigure', obj.rig.getDevice(obj.amp));
            end

            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.JitteredNoiseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType', obj.onlineAnalysis,... 
                    'stixelSize', obj.stixelSize, 'stepsPerStixel', double(obj.stepsPerStixel),...
                    'numXChecks', obj.numXChecks, 'numYChecks', obj.numYChecks,...
                    'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                    'frameRate', obj.frameRate, 'numFrames', obj.numFrames);
            end
        end

 
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            checkerboard = stage.builtin.stimuli.Image(obj.imageMatrix(:,:,1));
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
            preF = floor(obj.preTime/1000 * obj.frameRate);
            stimF = floor(obj.stimTime/1000 * obj.frameRate);

            imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                @(state)setStixels(obj, state.frame - preF, stimF));
            p.addController(imgController);

            function s = setStixels(obj, frame, stimFrames)
                if frame > 0 && frame <= stimFrames
                    s = squeeze(obj.imageMatrix(:,:,frame));
                else
                    s = squeeze(obj.imageMatrix(:,:,1));
                end
            end
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Deal with the seed.
            if obj.randsPerRep == 0 
                obj.seed = 1;
            elseif obj.randsPerRep < 0
                obj.seed = RandStream.shuffleSeed;
            elseif obj.randsPerRep > 0 && (mod(obj.numEpochsCompleted+1,obj.randsPerRep+1) == 0)
                obj.seed = 1;
            else
                obj.seed = RandStream.shuffleSeed;
            end
            
            obj.imageMatrix = manookinlab.util.getJitteredNoiseFrames(obj.numXStixels, obj.numYStixels, obj.numXChecks, obj.numYChecks, obj.numFrames, obj.stepsPerStixel, obj.seed);
            % Multiply by the contrast and convert to uint8.
            obj.imageMatrix = obj.contrast * obj.imageMatrix;
            obj.imageMatrix = uint8(255*(obj.backgroundIntensity*obj.imageMatrix + obj.backgroundIntensity));
            
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
