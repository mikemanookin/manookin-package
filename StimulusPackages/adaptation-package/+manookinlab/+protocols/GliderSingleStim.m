classdef GliderSingleStim < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 10500                % Stimulus duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        waitTime = 0                    % Stimulus wait duration (ms)
        stixelSize = 25                 % Stixel edge size (pixels)
        contrast = 0.5                  % Contrast (0 - 1)
        orientation = 0                 % Texture orientation (degrees)
        stimulusClass = 'uncorrelated'  % Correlated noise type
        dimensionality = '1-d'          % Stixel dimensionality
        innerRadius = 0                 % Inner mask radius in pixels.
        outerRadius = 120               % Outer mask radius in pixels.
        randomSeed = true               % Random or repeating seed
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular'% Online analysis type.
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        numberOfAverages = uint16(120)  % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        dimensionalityType = symphonyui.core.PropertyType('char', 'row', {'1-d', '2-d'});
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'uncorrelated','gaussian', '2-point positive', '2-point negative', '3-point diverging positive', '3-point converging positive', '3-point diverging negative', '3-point converging negative'})
        noiseStream
        seed
        frameSequence
        numXChecks
        numYChecks
        stixelDims
        numStimFrames
        parity
        stimulusType
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            % Calculate the number of frames.
            obj.numStimFrames = ceil(obj.stimTime/1000*obj.frameRate) + 10;
            
            % Calculate the X/Y stixels.
            obj.numYChecks = ceil(min(obj.outerRadius*2,obj.canvasSize(2))/obj.stixelSize);
            if strcmpi(obj.dimensionality, '1-d')
                obj.numXChecks = 1;
                obj.stixelDims = [min(obj.outerRadius*2,obj.canvasSize(1)) obj.stixelSize];
            else
                obj.numXChecks = ceil(min(obj.outerRadius*2,obj.canvasSize(1))/obj.stixelSize);
                obj.stixelDims = obj.stixelSize*ones(1,2);
            end
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            if ~obj.randomSeed
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',[0 0 0]);
            elseif strcmp(obj.stimulusClass, 'uncorrelated') && ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.SpatialNoiseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType', obj.onlineAnalysis, 'stixelSize', obj.stixelSize,...
                    'numXChecks', obj.numXChecks, 'numYChecks', obj.numYChecks,...
                    'noiseClass', 'binary', 'chromaticClass', 'achromatic',...
                    'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                    'frameRate', obj.frameRate, 'numFrames', obj.numStimFrames);
            elseif strcmp(obj.stimulusClass, 'gaussian') && ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.SpatialNoiseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType', obj.onlineAnalysis, 'stixelSize', obj.stixelSize,...
                    'numXChecks', obj.numXChecks, 'numYChecks', obj.numYChecks,...
                    'noiseClass', 'gaussian', 'chromaticClass', 'achromatic',...
                    'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                    'frameRate', obj.frameRate, 'numFrames', obj.numStimFrames);
            end
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            if strcmp(obj.stimulusType, 'uncorrelated')
                obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
                obj.frameSequence = (obj.noiseStream.rand(obj.numYChecks, obj.numXChecks, ...
                    obj.numStimFrames) > 0.5);
            elseif strcmp(obj.stimulusType, 'gaussian')
                obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
                obj.frameSequence = (0.3*obj.noiseStream.randn(obj.numYChecks, obj.numXChecks, obj.numStimFrames));
            else
                % Get the glider matrix.
                switch obj.stimulusType
                    case '2-point'
                        glider = [0 1 1; 1 1 0];
                    case '3-point diverging'
                        glider = [0 1 1; 1 1 1; 1 1 0];
                    case '3-point converging'
                        glider = [0 0 0; 1 0 0; 1 0 1];
                end

                % Get the parity.
                switch obj.parity
                    case 'positive'
                        par = 0;
                    otherwise
                        par = 1;
                end
            
                obj.frameSequence = makeGlider(obj.numYChecks, obj.numXChecks, ...
                    obj.numStimFrames, glider, par, obj.seed);
            end
            % Set the contrast.
            if ~strcmp(obj.stimulusType, 'gaussian')
                obj.frameSequence = obj.contrast * (2 * obj.frameSequence - 1);
            end
            
            % Convert to contrast.
            obj.frameSequence = obj.frameSequence*obj.backgroundIntensity + obj.backgroundIntensity;
%             obj.frameSequence(obj.frameSequence <= 0) = obj.frameSequence(obj.frameSequence <= 0)*obj.backgroundIntensity + obj.backgroundIntensity;

            % Convert to 8-bit integer.
            obj.frameSequence = uint8(obj.frameSequence * 255);
            
            % Create your noise image.
            imageMatrix = uint8((zeros(obj.numYChecks, obj.numXChecks)) * 255);
            checkerboard = stage.builtin.stimuli.Image(imageMatrix);
            checkerboard.position = obj.canvasSize / 2 + obj.centerOffset;
            checkerboard.size = [obj.numXChecks obj.numYChecks] .* obj.stixelDims;
            checkerboard.orientation = obj.orientation;
            
            % Set the minifying and magnifying functions to form discrete
            % stixels.
            checkerboard.setMinFunction(GL.NEAREST);
            checkerboard.setMagFunction(GL.NEAREST);
            
            % Add the stimulus to the presentation.
            p.addStimulus(checkerboard);
            
            %--------------------------------------------------------------
            % Size is 0 to 1
%             sz = (obj.outerRadius*2)/min(obj.canvasSize);
%             % Create the outer mask.
%             if sz < 1
%                 aperture = stage.builtin.stimuli.Rectangle();
%                 aperture.position = obj.canvasSize/2;
%                 aperture.color = obj.backgroundIntensity;
%                 aperture.size = obj.canvasSize;
%                 [x,y] = meshgrid(linspace(-obj.canvasSize(1)/2,obj.canvasSize(1)/2,obj.canvasSize(1)), ...
%                     linspace(-obj.canvasSize(2)/2,obj.canvasSize(2)/2,obj.canvasSize(2)));
%                 % Center the stimulus.
%                 x = x - obj.centerOffset(1);
%                 y = y + obj.centerOffset(2);
%                 distanceMatrix = sqrt(x.^2 + y.^2);
%                 circle = uint8((distanceMatrix >= obj.outerRadius) * 255);
%                 mask = stage.core.Mask(circle);
%                 aperture.setMask(mask);
%                 p.addStimulus(aperture); %add aperture
%             end
            %--------------------------------------------------------------

            gridVisible = stage.builtin.controllers.PropertyController(checkerboard, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(gridVisible);
            
            imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                @(state)frameSeq(obj, state.time - (obj.preTime+obj.waitTime)*1e-3));
            p.addController(imgController);
            
            function s = frameSeq(obj, time)
                if time >= 0 && time <= obj.stimTime*1e-3
                    frame = floor(obj.frameRate * time) + 1;
                    s = squeeze(obj.frameSequence(:, :, frame));
                else
                    s = squeeze(obj.frameSequence(:, :, 1));
                end
            end
            
            % Create the background inner ring.
            if obj.innerRadius > 0
                bg = stage.builtin.stimuli.Ellipse();
                bg.color = obj.backgroundIntensity;
                bg.radiusX = obj.innerRadius;
                bg.radiusY = obj.innerRadius;
                bg.position = obj.canvasSize/2 + obj.centerOffset;
                p.addStimulus(bg);
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Deal with the seed.
            if obj.randomSeed
                obj.seed = RandStream.shuffleSeed;
            else
                obj.seed = 1;
            end
            
            % Seed the random number generator.
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            if isempty(strfind(obj.stimulusClass,'uncorrelated')) && isempty(strfind(obj.stimulusClass,'gaussian'))
                % Check parity.
                if isempty(strfind(obj.stimulusClass,'positive'))
                    obj.parity = 'negative';
                    obj.stimulusType = strrep(obj.stimulusClass,' negative','');
                else
                    obj.parity = 'positive';
                    obj.stimulusType = strrep(obj.stimulusClass,' positive','');
                end
            else
                obj.stimulusType = obj.stimulusClass;
            end
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('numXChecks', obj.numXChecks);
            epoch.addParameter('numYChecks', obj.numYChecks);
        end
        
        % Same presentation each epoch in a run. Replay.
        function controllerDidStartHardware(obj)
            controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            if (obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < obj.numberOfAverages) && ~obj.randomSeed
                obj.rig.getDevice('Stage').replay
            else
                obj.rig.getDevice('Stage').play(obj.createPresentation());
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