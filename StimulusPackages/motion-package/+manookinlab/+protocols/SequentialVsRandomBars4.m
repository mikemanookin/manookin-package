classdef SequentialVsRandomBars4 < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Stimulus leading duration (ms)
        stimTime = 500                  % Stimulus duration (ms)
        tailTime = 500                  % Stimulus trailing duration (ms)
        waitTime = 0                    % Stimulus wait time (ms)
        frameDwell = 2                  % Frame dwell
        barSize = [25 200]              % Bar size (pixels)
        numberOfBars = 8                % Number of bars
        contrast = 0.5                  % Bar contrast (-1 : 1)
        orientation = 0                 % Bar orientation (degrees)
        surroundContrasts = [-0.25 0 0.25]% Surround contrast
        surroundApertureRadius = 250    % Surround aperture radius (pix)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular'% Online analysis type.
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        numberOfAverages = uint16(120)  % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        sequenceNames = {'sequential', 'random'}
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
        surroundContrast
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
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
            
            % Create the surround stimulus.
            if obj.surroundContrast ~= 0
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = obj.canvasSize/2 + obj.centerOffset;
                aperture.color = obj.surroundContrast*obj.backgroundIntensity + obj.backgroundIntensity;
                aperture.size = [max(obj.canvasSize) max(obj.canvasSize)];
                if obj.surroundApertureRadius > 0 && obj.surroundApertureRadius < min(obj.canvasSize/2)
                    mask = stage.core.Mask.createCircularAperture(obj.surroundApertureRadius*2/max(obj.canvasSize), 1024);
                    aperture.setMask(mask);
                end
                p.addStimulus(aperture);
                % Make the aperture visible only during the stimulus time.
                apertureVisible = stage.builtin.controllers.PropertyController(aperture, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time <= (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(apertureVisible);
            end
            
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
                if obj.numberOfBars == 4
                    barSeq = obj.validRandomSequence();
                elseif obj.numberOfBars == 8 && ~strcmpi(obj.onlineAnalysis,'extracellular')
                    barSeq = obj.validRandomSequence();
                else
                    obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
                    barSeq = obj.noiseStream.randperm(obj.numberOfBars);
                end
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
        
        function barSeq = validRandomSequence(obj)
            switch obj.numberOfBars
                case 4
                    u = [
                        1 3 4 2;
                        1 4 2 3;
                        2 4 1 3;
                        4 1 3 2;
                        2 4 1 3;
                        3 1 4 2;
                        4 2 1 3;
                        ];
                case 8
                    u = [
                        7     2     1     5     3     6     8     4
                        1     2     4     3     8     7     5     6
                        7     6     3     2     1     8     4     5
                        7     5     3     8     2     1     4     6
                        6     5     4     1     2     3     7     8
                        6     8     5     1     2     4     3     7
                        4     2     3     5     1     8     6     7
                        1     8     7     5     3     2     4     6
                        7     4     5     1     8     6     3     2
                        4     8     6     5     3     7     2     1
                        3     5     2     1     7     4     8     6
                        3     5     7     1     8     4     6     2
                        3     1     5     2     6     8     7     4
                        2     5     3     7     4     8     1     6
                        4     6     7     3     1     8     2     5
                        3     7     2     4     6     5     8     1
                        4     7     3     2     8     6     1     5
                        7     4     1     5     8     3     6     2
                        1     5     3     8     4     7     2     6
                        6     4     8     3     7     2     5     1
                        3     5     7     1     4     2     8     6
                        8     2     7     5     3     6     4     1
                        4     7     2     6     8     5     1     3
                        5     1     6     8     3     7     4     2
                        ];
            end
            
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            barSeq = u(ceil(obj.noiseStream.rand*size(u,1)),:);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current sequence name.
            obj.sequenceName = obj.sequenceNames{obj.sequence( obj.numEpochsCompleted+1 )};
            obj.surroundContrast = obj.surroundContrasts(mod(floor(obj.numEpochsCompleted/2),length(obj.surroundContrasts))+1);
            
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
            epoch.addParameter('surroundContrast',obj.surroundContrast);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end