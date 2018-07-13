classdef MotionNoise2 < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Stimulus leading duration (ms)
        stimTime = 16000                % Stimulus duration (ms)
        tailTime = 1000                 % Stimulus trailing duration (ms)
        stixelSize = 25                 % Stixel edge size (pixels)
        contrast = 1.0                  % Noise contrast (0 : 1)
        velocity = 16250                % Noise velocity (pixels/sec)
        correlation = 2                 % Noise correlation (1/f^x)
        orientation = 0                 % Bar orientation (degrees)
        innerRadius = 0                 % Inner mask radius in pixels.
        outerRadius = 120               % Outer mask radius in pixels.
        randomSeed = false              % Random or repeating seed
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Online analysis type.
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        numberOfAverages = uint16(128)  % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        seed
        frameSequence
        numXChecks
        numYChecks
        numStimFrames
        sequence
        noiseStream
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if length(obj.v) > 1
                colors = pmkmp(length(obj.velocity),'CubicYF');
            else
                colors = [0 0 0];
            end
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'velocity'});
            
            % Calculate the number of frames.
            obj.numStimFrames = ceil(obj.stimTime*1e-3*obj.frameRate) + 10;
            
            % Calculate the X/Y stixels.
            obj.numXChecks = ceil(min(obj.outerRadius*2,obj.canvasSize(1))/obj.stixelSize);
            obj.numYChecks = ceil(min(obj.outerRadius*2,obj.canvasSize(2))/obj.stixelSize);
        end
        
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create the frame sequence.
            obj.frameSequence = getMotionNoiseFrames(...
                obj.numXChecks, obj.numYChecks, obj.numStimFrames, obj.velocity, obj.seed, obj.frameRate, obj.correlation);
            % Set the contrast.
            obj.frameSequence = obj.contrast * obj.frameSequence;
            
            % Create the uncorrelated noise sequence at the end.
            index = ceil(obj.stimTime/2*1e-3*obj.frameRate);
            numUncorr = obj.numStimFrames - index;
            % Generate Gaussian noise sequence.
            gNoise = obj.contrast * 0.3 * obj.noiseStream.randn(obj.numYChecks,obj.numXChecks,numUncorr);
            obj.frameSequence(:,:,index+1:end) = gNoise;
            
            % Convert to contrast.
            obj.frameSequence = obj.frameSequence*obj.backgroundIntensity + obj.backgroundIntensity;

            % Convert to 8-bit integer.
            obj.frameSequence = uint8(obj.frameSequence * 255);
            
            % Create your noise image.
            imageMatrix = uint8((zeros(obj.numYChecks, obj.numXChecks)) * 255);
            checkerboard = stage.builtin.stimuli.Image(imageMatrix);
            checkerboard.position = obj.canvasSize / 2;
            checkerboard.size = [obj.numXChecks obj.numYChecks] * obj.stixelSize;
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
                @(state)frameSeq(obj, state.time - obj.preTime*1e-3));
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
            
            % Save the seed.
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