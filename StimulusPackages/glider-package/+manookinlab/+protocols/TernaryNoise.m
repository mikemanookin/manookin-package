classdef TernaryNoise < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 6000                 % Stimulus duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        waitTime = 1000                 % Stimulus wait duration (ms)
        orientation = 0                 % Texture orientation (degrees)
        stixelSize = 50                 % Stixel edge size (pixels)
        contrast = 0.7                  % Contrast (0 - 1)
        dimensionality = '2-d'          % Stixel dimensionality
        dx = 1                          % The dx shift per frame.
        corr = 0:6                      % Correlation duration (frames)
        noiseClass = 'binary'           % Noise type (binary or gaussian)
        innerRadius = 0                 % Inner mask radius in pixels.
        outerRadius = 1000              % Outer mask radius in pixels.
        randomSeed = true               % Random or repeating seed
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular'         % Online analysis type.
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        numberOfAverages = uint16(70)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        dimensionalityType = symphonyui.core.PropertyType('char', 'row', {'1-d', '2-d'})
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary', 'gaussian'});
        noiseStream
        seed
        frameSequence
        numXChecks
        numYChecks
        stixelDims
        correlationFrames
        numStimFrames
        corrSeq
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if length(obj.corr) > 1
                colors = pmkmp(length(obj.corr),'CubicYF');
            else
                colors = [0 0 0];
            end
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'correlationFrames'});
            
            % Calculate the number of frames.
            obj.numStimFrames = ceil(obj.stimTime/1000*obj.frameRate) + 10;
            
            % Calculate the X/Y stixels.
            obj.numXChecks = ceil(obj.canvasSize(1)/obj.stixelSize);
            if strcmpi(obj.dimensionality, '1-d')
                obj.numYChecks = 1;
                obj.stixelDims = [obj.stixelSize obj.canvasSize(2)];
            else
                obj.numYChecks = ceil(obj.canvasSize(2)/obj.stixelSize);
                obj.stixelDims = obj.stixelSize*ones(1,2);
            end
            
            % Get the correlation sequence.
            obj.corrSeq = obj.corr(:) * ones(1, obj.numberOfAverages);
            obj.corrSeq = obj.corrSeq(:)';
            % Just take the ones you need.
            obj.corrSeq = obj.corrSeq( 1 : obj.numberOfAverages );
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create the frame sequence.
            if strcmp(obj.noiseClass, 'binary')
                eta = double(obj.noiseStream.randn(obj.numYChecks, obj.numXChecks, obj.numStimFrames) > 0)*2 - 1;
            else
                eta = 0.3*obj.noiseStream.randn(obj.numYChecks, obj.numXChecks, obj.numStimFrames);
            end
            
            obj.frameSequence = (eta + circshift(eta, [0, obj.dx, obj.correlationFrames])) / 2;
            % Set the contrast.
            obj.frameSequence = obj.contrast * obj.frameSequence;
            % Convert to contrast.
            obj.frameSequence(obj.frameSequence <= 0) = obj.frameSequence(obj.frameSequence <= 0)*obj.backgroundIntensity + obj.backgroundIntensity;

            % Convert to 8-bit integer.
            obj.frameSequence = uint8(obj.frameSequence * 255);
            
            % Create your noise image.
            imageMatrix = uint8((zeros(obj.numYChecks, obj.numXChecks)) * 255);
            checkerboard = stage.builtin.stimuli.Image(imageMatrix);
            checkerboard.position = obj.canvasSize / 2;
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
            sz = (obj.outerRadius*2)/min(obj.canvasSize);
            % Create the outer mask.
            if sz < 1
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = obj.canvasSize/2;
                aperture.color = obj.backgroundIntensity;
                aperture.size = obj.canvasSize;
                [x,y] = meshgrid(linspace(-obj.canvasSize(1)/2,obj.canvasSize(1)/2,obj.canvasSize(1)), ...
                    linspace(-obj.canvasSize(2)/2,obj.canvasSize(2)/2,obj.canvasSize(2)));
                % Center the stimulus.
                x = x - obj.centerOffset(1);
                y = y + obj.centerOffset(2);
                distanceMatrix = sqrt(x.^2 + y.^2);
                circle = uint8((distanceMatrix >= obj.outerRadius) * 255);
                mask = stage.core.Mask(circle);
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
            %--------------------------------------------------------------

            gridVisible = stage.builtin.controllers.PropertyController(checkerboard, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(gridVisible);
            
            imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                @(state)frameSeq(obj, state.time - (obj.preTime+obj.waitTime)*1e-3));
            p.addController(imgController);
            
            function s = frameSeq(obj, time)
                if time >= 0 && time <= obj.stimTime*1e-3;
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
            
            % Get the correlation frames.
            obj.correlationFrames = obj.corrSeq( obj.numEpochsCompleted+1 );
            
            dt = obj.correlationFrames / obj.frameRate * 1000; % dt in msec
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('numXChecks', obj.numXChecks);
            epoch.addParameter('numYChecks', obj.numYChecks);
            epoch.addParameter('correlationFrames', obj.correlationFrames);
            epoch.addParameter('dtMsec', dt);
        end
        
        % Same presentation each epoch in a run. Replay.
        function controllerDidStartHardware(obj)
            controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            if (obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < obj.numberOfAverages) && ~obj.randomSeed && length(obj.corr) == 1
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