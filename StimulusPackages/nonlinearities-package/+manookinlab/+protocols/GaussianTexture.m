classdef GaussianTexture < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Stimulus leading duration (ms)
        stimTime = 500                  % Stimulus duration (ms)
        tailTime = 500                  % Stimulus trailing duration (ms)
        contrast = 1.0                  % Contrast (0 - 1)
        standardDevs = 5:5:40           % Standard deviations (pixels)
        innerRadius = 0                 % Inner mask radius in pixels.
        outerRadius = 1000              % Outer mask radius in pixels.
        randomSeed = true               % Random or repeating seed
        randomSequence = true           % Random or repeated sequence
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular'         % Online analysis type.
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        numberOfAverages = uint16(40)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        seed
        stdDev
        sequence
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.sMTFFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                'temporalType', 'pulse', 'spatialType', 'spot', ...
                'xName', 'stdDev', 'xaxis', unique(obj.standardDevs));
            
            % Get the number of repeats of the sequence.
            numReps = ceil(double(obj.numberOfAverages) / length(obj.standardDevs));
            
            sq = zeros(length(obj.standardDevs), numReps);
            
            for k = 1 : numReps
                if obj.randomSequence
                    sq(:,k) = randperm(length(obj.standardDevs));
                else
                    sq(:,k) = 1 : length(obj.standardDevs);
                end
            end
            
            % Get the sequence.
            obj.sequence = obj.standardDevs(sq(:)');
            % Just take the ones you need.
            obj.sequence = obj.sequence( 1 : obj.numberOfAverages );
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Generate the texture.
            imageMatrix = generateTexture(min(obj.canvasSize), obj.stdDev, obj.contrast);
            
            % Create your noise image.
            imageMatrix = uint8(imageMatrix * 255);
            checkerboard = stage.builtin.stimuli.Image(imageMatrix);
            checkerboard.position = obj.canvasSize / 2;
            checkerboard.size = min(obj.canvasSize)*ones(1,2);
            
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
            
            % Get the standard deviation.
            obj.stdDev = obj.sequence( obj.numEpochsCompleted+1 );
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('stdDev', obj.stdDev);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end