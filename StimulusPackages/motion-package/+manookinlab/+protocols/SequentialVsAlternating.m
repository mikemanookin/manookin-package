classdef SequentialVsAlternating < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Stimulus leading duration (ms)
        stimTime = 500                  % Stimulus duration (ms)
        tailTime = 500                  % Stimulus trailing duration (ms)
        waitTime = 0                    % Stimulus wait time (ms)
        frameDwell = 2                  % Frame dwell
        barSize = [150 1200]            % Bar size (pixels)
        numberOfBars = 8                % Number of bars
        contrast = 0.75                 % Bar contrast (-1 : 1)
        orientation = 0                 % Bar orientation (degrees)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Online analysis type.
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        numberOfAverages = uint16(60)  % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        sequenceNames
        sequenceName
        sequence
        seed
        frameSequence
        latticeSize
        actualStimFrames
        noiseStream
        orientationRads
        startPosition
        positions
        speed
        stimDur
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.sequenceNames = {'sequential', 'random'};
            
            if length(obj.sequenceNames) > 1
                colors = pmkmp(length(obj.sequenceNames),'CubicYF');
            else
                colors = [0 0 0];
            end
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'sequenceName'});
            
            % Get the correlation sequence.
            numReps = ceil(double(obj.numberOfAverages)/length(obj.sequenceNames));
            obj.sequence = (1 : length(obj.sequenceNames))' * ones(1, numReps);
            obj.sequence = obj.sequence(:)';
            % Just take the ones you need.
            obj.sequence = obj.sequence( 1 : obj.numberOfAverages );
            
            % Get the number of actual stimulus frames.
            obj.actualStimFrames = obj.frameDwell * obj.numberOfBars;
        end
        
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            % Create the stimulus.
            bars = stage.builtin.stimuli.Rectangle();
            bars.position = obj.canvasSize/2 + obj.centerOffset;
            bars.size = obj.barSize;
            bars.orientation = obj.orientation;
            % Convert from contrast to intensity.
            if obj.backgroundIntensity > 0
                bars.color = obj.backgroundIntensity*obj.contrast+obj.backgroundIntensity;
            else
                bars.color = obj.contrast;
            end

            % Add the stimulus to the presentation.
            p.addStimulus(bars);

            % Calculate the stimulus duration.
            obj.stimDur = obj.actualStimFrames / obj.frameRate;
            gridVisible = stage.builtin.controllers.PropertyController(bars, 'visible', ...
                @(state)state.time >= (obj.preTime+obj.waitTime) * 1e-3 && state.time <= (obj.preTime+obj.waitTime) * 1e-3 + obj.stimDur);
            p.addController(gridVisible);
            
            % Bar position controller
            if ~isempty(strfind(obj.sequenceName, 'random'))
                barPosition = stage.builtin.controllers.PropertyController(bars, 'position', ...
                    @(state)randomTable(obj, state.time - (obj.preTime+obj.waitTime)*1e-3));
            else
                barPosition = stage.builtin.controllers.PropertyController(bars, 'position', ...
                    @(state)motionTable(obj, state.time - (obj.preTime+obj.waitTime)*1e-3));
            end
            p.addController(barPosition);
            
            function p = motionTable(obj, time)
                % Calculate the increment with time.  
                inc = time * obj.speed + obj.startPosition;
                
                p = [cos(obj.orientationRads) sin(obj.orientationRads)] .* (inc*ones(1,2)) + obj.canvasSize/2 + obj.centerOffset;
            end
            
            function p = randomTable(obj, time)
                if time >=0 && time <= obj.stimDur
                    frame = floor(obj.frameRate * time) + 1;
                    p = [cos(obj.orientationRads) sin(obj.orientationRads)] .* (obj.positions(frame)*ones(1,2)) + obj.canvasSize/2 + obj.centerOffset;
                else
                    p = 5000*ones(1,2);
                end
            end
        end
        
        function barSeq = generateFrameSequence(obj)
            % Calculate the orientation in radians.
            obj.orientationRads = obj.orientation/180*pi;
            
            % Calculate the bar speed in pix/sec.
            obj.speed = obj.barSize(1)*obj.frameRate/obj.frameDwell;
            
            % Generate the frame sequence based on the sequence name.
            if ~isempty(strfind(obj.sequenceName,'sequential'))
                barSeq = 1 : obj.numberOfBars;
            else
                obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
                barSeq = obj.noiseStream.randperm(obj.numberOfBars);
                if barSeq(1) == obj.numberOfBars
                    barSeq(1) = obj.numberOfBars-1;
                end
                % Make the alternating bars.
                foo = [barSeq(1) barSeq(1)+1]'*ones(1,length(barSeq));
                foo = foo(:)';
                barSeq = foo(1 : obj.numberOfBars);
            end
            
            if obj.frameDwell > 1
                barSeq = ones(obj.frameDwell,1)*barSeq;
                barSeq = barSeq(:)';
            end
            
            % Calculate the base bar position.
            obj.startPosition = -(obj.numberOfBars/2*obj.barSize(1)) + obj.barSize(1)/2;
            % Get the sequence positions. Add extra seq on the end in case
            % of rounding error.
            obj.positions = [obj.startPosition + (barSeq-1)*obj.barSize(1) 5000*ones(1,10)];
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current sequence name.
            obj.sequenceName = obj.sequenceNames{obj.sequence( obj.numEpochsCompleted+1 )};
            
            % Get the seed if it's a random sequence.
            if ~isempty(strfind(obj.sequenceName, 'random'))
                obj.seed = RandStream.shuffleSeed;
                epoch.addParameter('seed', obj.seed);
            end

            % Save the sequence name
            epoch.addParameter('sequenceName', obj.sequenceName);
            epoch.addParameter('actualStimFrames', obj.actualStimFrames);
            
            % Generate the frame sequence.
            barSeq = obj.generateFrameSequence();
            epoch.addParameter('barSequence', barSeq);
            epoch.addParameter('speed',obj.speed');
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end