classdef SequentialVsRandomBars3 < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Stimulus leading duration (ms)
        stimTime = 1000                 % Stimulus duration (ms)
        tailTime = 500                  % Stimulus trailing duration (ms)
        waitTime = 0                    % Stimulus wait time (ms)
        frameDwell = 1                  % Frame dwell
        barSize = [150 1200]            % Bar size (pixels)
        numberOfBars = 8                % Number of bars
        contrast = 0.75                 % Bar contrast (-1 : 1)
        orientation = 0                 % Bar orientation (degrees)
        surroundClass = 'none'          % Surround stimulus
        surroundContrast = 1.0           % Grating contrast (0-1)
        surroundStdev = 50            % Grating bar width (pix)
        surroundApertureRadius = 250     % Grating aperture radius (pix)
        surroundTemporalFrequency = 4.0  % Grating temporal frequency (Hz)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Online analysis type.
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        numberOfAverages = uint16(120)  % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        surroundClassType = symphonyui.core.PropertyType('char', 'row', {'none', 'plaid', 'noise'})
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
            
            % Check the surround type.
            if strcmp(obj.surroundClass, 'none')
                obj.sequenceNames = {'sequential', 'random'};
            else
                obj.sequenceNames = {'sequential', 'random', 'sequential+surround', 'random+surround'};
            end
            
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
            if ~isempty(strfind(obj.sequenceName,'surround'))
                if strcmp(obj.surroundClass, 'plaid')
                    grating1 = stage.builtin.stimuli.Grating('sine');
                    grating1.orientation = 30;
                    grating1.size = sqrt(2*max(obj.canvasSize)^2)*ones(1,2);
                    grating1.position = obj.canvasSize/2 + obj.centerOffset;
                    grating1.spatialFreq = 1/(2*obj.surroundStdev); %convert from bar width to spatial freq
                    grating1.contrast = obj.surroundContrast;
                    grating1.color = 2*obj.backgroundIntensity;
                    % Add the grating.
                    p.addStimulus(grating1);

                    grating2 = stage.builtin.stimuli.Grating('sine');
                    grating2.orientation = -60;
                    grating2.size = sqrt(2*max(obj.canvasSize)^2)*ones(1,2);
                    grating2.position = obj.canvasSize/2 + obj.centerOffset;
                    grating2.spatialFreq = 1/(2*obj.surroundStdev); %convert from bar width to spatial freq
                    grating2.contrast = obj.surroundContrast;
                    grating2.color = 2*obj.backgroundIntensity;
                    grating2.opacity = 0.5;
                    % Add the grating.
                    p.addStimulus(grating2);

                    % Make the grating visible only during the stimulus time.
                    grating1Visible = stage.builtin.controllers.PropertyController(grating1, 'visible', ...
                        @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                    p.addController(grating1Visible);

                    grating2Visible = stage.builtin.controllers.PropertyController(grating2, 'visible', ...
                        @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                    p.addController(grating2Visible);

                    %--------------------------------------------------------------
                    % Control the grating phase.
                    grating1PhaseController = stage.builtin.controllers.PropertyController(grating1, 'phase', @(state)state.time * obj.surroundTemporalFrequency * 360);
                    grating2PhaseController = stage.builtin.controllers.PropertyController(grating2, 'phase', @(state)state.time * obj.surroundTemporalFrequency * 180);
                    p.addController(grating1PhaseController);
                    p.addController(grating2PhaseController);
                else
                    % Calculate the number of X/Y checks.
                    obj.numXChecks = ceil(obj.canvasSize(1)/obj.surroundStdev);
                    obj.numYChecks = ceil(obj.canvasSize(2)/obj.surroundStdev);
                    % Seed the random number generator.
                    obj.noiseStream = RandStream('mt19937ar', 'Seed', 1);
                    
                    checkerboard = stage.builtin.stimuli.Image(uint8(255*obj.surroundContrast*(rand(obj.numYChecks,obj.numXChecks) > 0.5)));
                    checkerboard.position = obj.canvasSize / 2;
                    checkerboard.size = [obj.numXChecks obj.numYChecks] * obj.surroundStdev;
                    
                    checkerboard.setMinFunction(GL.NEAREST);
                    checkerboard.setMagFunction(GL.NEAREST);

                    % Add the stimulus to the presentation.
                    p.addStimulus(checkerboard);

                    checkVisible = stage.builtin.controllers.PropertyController(checkerboard, 'visible', ...
                        @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                    p.addController(checkVisible);
                    
                    checkController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                        @(state)setStixels(obj, state.time - obj.preTime * 1e-3));
                    p.addController(checkController);
                end
                % Create the aperture.
                if obj.surroundApertureRadius > 0 && obj.surroundApertureRadius < min(obj.canvasSize/2)
                    bg = stage.builtin.stimuli.Ellipse();
                    bg.color = obj.backgroundIntensity;
                    bg.radiusX = obj.surroundApertureRadius;
                    bg.radiusY = obj.surroundApertureRadius;
                    bg.position = obj.canvasSize/2 + obj.centerOffset;
                    p.addStimulus(bg);
                end
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
            
            function s = setStixels(obj, time)
                if time >= 0 && time < obj.stimTime * 1e-3
                    s = uint8(255*obj.surroundContrast*(obj.noiseStream.rand(obj.numYChecks,obj.numXChecks) > 0.5));
                else
                    s = uint8(255*obj.backgroundIntensity*ones(obj.numYChecks,obj.numXChecks));
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