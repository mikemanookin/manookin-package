classdef TernaryRings < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 6000                 % Stimulus duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        waitTime = 1000                 % Stimulus wait duration (ms)
        tiltDirection = 'outward'       % Inward or outward tilt?
        innerRadius = 50                % Inner mask radius in pixels.
        outerRadius = 200               % Outer mask radius in pixels.
        ringWidth = 25                  % Ring width (pix)
        corr = 0:6                      % Correlation duration (frames)
        randomSeed = false              % Random or repeating seed
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        onlineAnalysis = 'none'         % Online analysis type.
        numberOfAverages = uint16(35)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        tiltDirectionType = symphonyui.core.PropertyType('char', 'row', {'outward', 'inward'})
        noiseStream
        seed
        numRings
        numStimFrames
        frameSequence
        correlationFrames
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
            
            % Calculate the number of rings.
            obj.numRings = ceil((obj.outerRadius - obj.innerRadius) / obj.ringWidth);
            
            % Calculate the number of frames.
            obj.numStimFrames = ceil(obj.stimTime/1000*obj.frameRate) + 10;
            
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
            eta = double(obj.noiseStream.randn(obj.numStimFrames, obj.numRings) > 0)*2 - 1;
            
            obj.frameSequence = (eta + circshift(eta, [obj.correlationFrames, 1])) / 2;
            % Convert to contrast.
            obj.frameSequence(obj.frameSequence < 1) = obj.frameSequence(obj.frameSequence < 1)*obj.backgroundIntensity + obj.backgroundIntensity;
            
            % Flip the frame sequence for outward tilt.
            if strcmp(obj.tiltDirection, 'outward')
                obj.frameSequence = fliplr(obj.frameSequence);
            end
            
            % Calculate the outer radii.
            radii = obj.outerRadius - obj.ringWidth*(0:obj.numRings-1);

            % Create the rings.
            for k = 1 : obj.numRings
                spot = stage.builtin.stimuli.Ellipse();
                spot.color = obj.backgroundIntensity;
                spot.radiusX = radii(k);
                spot.radiusY = radii(k);
                spot.position = obj.canvasSize/2 + obj.centerOffset;
                p.addStimulus(spot);

                spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(spotVisible);

                % Bar position controller
                spotColor = stage.builtin.controllers.PropertyController(spot, 'color', ...
                    @(state)frameSeq(obj, state.time - (obj.preTime+obj.waitTime)*1e-3, k));
                p.addController(spotColor);
            end
            
            % Great the background inner ring.
            if obj.innerRadius > 0
                bg = stage.builtin.stimuli.Ellipse();
                bg.color = obj.backgroundIntensity;
                bg.radiusX = obj.innerRadius;
                bg.radiusY = obj.innerRadius;
                bg.position = obj.canvasSize/2 + obj.centerOffset;
                p.addStimulus(bg);
            end
            
            function c = frameSeq(obj, time, whichSpot)
                if time >= 0 && time <= obj.stimTime*1e-3;
                    frame = floor(obj.frameRate * time) + 1;
                    c = obj.frameSequence(frame, whichSpot);
                else
                    c = obj.frameSequence(1, whichSpot);
                end
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
            epoch.addParameter('numRings', obj.numRings);
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