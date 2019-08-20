classdef MotionCenterSurround < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stim leading duration (ms)
        motionTime = 1000               % Duration of background motion (ms)
        tailTime = 500                  % Stim trailing duration (ms)
        centerBarWidth = 40             % Center bar width in microns.
        numberOfCenterBars = 6          % Number of center bars
        centerFrameDwell = 1            % Frame dwell for center bars
        centerBarOrientation = 90       % Center bar orientation (degrees)
        apertureRadius = 250            % Aperture/blank radius in microns.
        delayTimes = [-100 -100]        % Delay time (ms)
        contrasts = [1 1]               % Center bar contrasts (-1:1)
        numBarPairs = 2                 % Number of background bar pairs (positive/negative contrast)
        surroundBarFrameDwell = 1       % Frame dwell for background bars
        surroundBarWidth = 60           % Background bar width (microns)
        surroundBarContrast = 1.0       % Background bar contrast (-1 : 1)
        surroundBarOrientation = 90     % Background bar orientation (degrees)
        backgroundIntensity = 0.5       % Background light intensity (0-1) 
        centerSequences = 'sequential-random-sequential180' % Center sequence on alternating trials.
        backgroundSequences = 'sequential-random' % Background sequence on alternating trials.
        onlineAnalysis = 'extracellular'% Online analysis type.
        numberOfAverages = uint16(120)   % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        centerSequencesType = symphonyui.core.PropertyType('char','row',{'sequential-sequential180','sequential-random','sequential-random-sequential180'})
        backgroundSequencesType = symphonyui.core.PropertyType('char','row',{'sequential-random','sequential-random-stationary'})
        contrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        delayTimesType = symphonyui.core.PropertyType('denserealdouble','matrix')
        seed
        frameSeq
        noiseStream2
        surroundBarOrientationRads
        thisCenterOffset
        positions
        centerBarWidthPix
        apertureRadiusPix
        surroundBarWidthPix
        centerClasses
        sequenceName
        backgroundClasses
        backgroundClass
        numBars
        delayTime
        contrast
        stimDur
        actualStimFrames
        centerBarOrientationRads
        speed
        centerPositions
        startPosition
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            obj.centerBarWidthPix = obj.rig.getDevice('Stage').um2pix(obj.centerBarWidth);
            obj.apertureRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.apertureRadius);
            obj.surroundBarWidthPix = obj.rig.getDevice('Stage').um2pix(obj.surroundBarWidth);
            
            % Get the number of actual stimulus frames.
            obj.actualStimFrames = obj.centerFrameDwell * obj.numberOfCenterBars;
            obj.stimDur = obj.actualStimFrames / obj.frameRate;
            % Calculate the bar speed in pix/sec.
            obj.speed = obj.centerBarWidthPix*obj.frameRate/obj.centerFrameDwell;
            % Calculate the base bar position.
            obj.startPosition = -(obj.numberOfCenterBars/2*obj.centerBarWidthPix) + obj.centerBarWidthPix/2;
            
            obj.numBars = round(obj.numBarPairs * 2);
            % Calculate the orientation in radians.
            obj.surroundBarOrientationRads = obj.surroundBarOrientation/180*pi;
            obj.centerBarOrientationRads = obj.centerBarOrientation/180*pi;
            
            switch obj.centerSequences
                case 'sequential-sequential180'
                    obj.centerClasses = {'sequential','sequential180'};
                case 'sequential-random'
                    obj.centerClasses = {'sequential','random'};
                case 'sequential-random-sequential180'
                    obj.centerClasses = {'sequential','random','sequential180'};
            end
            
            switch obj.backgroundSequences
                case 'sequential-random-stationary'
                    obj.backgroundClasses = {'sequential','random','stationary'};
                case 'sequential-random'
                    obj.backgroundClasses = {'sequential','random'};
            end

            % Get the center offset from Stage.
            obj.thisCenterOffset = obj.rig.getDevice('Stage').getCenterOffset();
            
            if ~strcmp(obj.onlineAnalysis, 'none')
%                 if length(unique(obj.delayTimes)) == 1
%                     obj.showFigure('manookinlab.figures.ContrastResponseFigure', ...
%                         obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
%                         'preTime',obj.preTime+obj.motionTime+obj.delayTimes(1),...
%                         'stimTime',ceil(obj.stimDur*1e3),...
%                         'contrasts',unique(obj.contrasts),...
%                         'groupBy','backgroundClass',...
%                         'groupByValues',obj.backgroundClasses,...
%                         'temporalClass','pulse');
%                 else
%                     obj.showFigure('manookinlab.figures.AdaptFlashFigure', ...
%                         obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
%                         'preTime',obj.preTime,...
%                         'flash1Duration',obj.motionTime,...
%                         'flash2Duration',obj.flashTime,...
%                         'flash1Contrasts',1:length(obj.backgroundClasses),...
%                         'flash2Contrasts',unique(obj.contrasts),...
%                         'ipis',obj.delayTimes);
%                 end
                
                
                if length(obj.backgroundClasses) == 2
                    colors = [0 0 0; 0.8 0 0];
                else
                    colors = [0 0 0; 0.8 0 0; 0 0.5 0; 0 0 0; 0.8 0 0; 0 0.5 0];
                end
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',colors,...
                    'groupBy',{'centerClass','backgroundClass'});
            end
        end
        
        function getBarPositions(obj)
            % Calculate the number of frames.
            numFrames = ceil(obj.motionTime*1e-3*obj.frameRate) + 16;
            % Calculate the number of positions.
            numPositions = floor(min(obj.canvasSize) / obj.surroundBarWidthPix);
            positionValues = linspace(-min(obj.canvasSize)/2+obj.surroundBarWidthPix/2,min(obj.canvasSize)/2-obj.surroundBarWidthPix/2,numPositions);
            positionValues = positionValues(:);
            
            obj.positions = zeros(numFrames, obj.numBars);
            
            offsetPerBar = floor(numPositions / obj.numBars);
            
            if strcmpi(obj.backgroundClass,'random')
                % Get the random sequence.
                numCycles = ceil(numFrames / numPositions);
                randSeq = zeros(numCycles*numPositions,1);
                for k = 1 : numCycles
                    idx = (k-1)*numPositions + (1 : numPositions);
                    randSeq(idx) = obj.noiseStream2.randperm(numPositions);
                end
                barSeq = randSeq(1 : numFrames);
            elseif strcmpi(obj.backgroundClass,'stationary')
                % Pick a single random spot to show the bar throughout.
                tmp = obj.noiseStream2.randperm(numPositions);
                barSeq = tmp(1)*ones(numFrames,1);
            else
                % Motion sequence
                barSeq = mod(0:numFrames-1,numPositions)' + 1;
            end
            
            if obj.surroundBarFrameDwell > 1
                nUniquePts = ceil(numFrames / obj.surroundBarFrameDwell);
                tmp = ones(obj.surroundBarFrameDwell,1) * barSeq(1:nUniquePts)';
                tmp = tmp(:);
                barSeq = tmp(1 : numFrames);
            end

            for k = 1 : obj.numBars
                seq = mod(barSeq+(k-1)*offsetPerBar-1,numPositions)+1;
                obj.positions(:,k) = positionValues(seq);
            end
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create the stimulus.
            for k = 1 : obj.numBars
                barSign = 2*mod(k,2)-1;
                bars = stage.builtin.stimuli.Rectangle();
                bars.position = obj.canvasSize/2 - obj.thisCenterOffset;
                bars.size = [obj.surroundBarWidthPix max(obj.canvasSize)];
                bars.orientation = obj.surroundBarOrientation;
                % Convert from contrast to intensity.
                if obj.backgroundIntensity > 0
                    bars.color = obj.backgroundIntensity*barSign*obj.surroundBarContrast+obj.backgroundIntensity;
                else
                    bars.color = obj.surroundBarContrast;
                end

                % Add the stimulus to the presentation.
                p.addStimulus(bars);

                % Make the bars visible only during the stimulus time.
                gridVisible = stage.builtin.controllers.PropertyController(bars, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(gridVisible);

                % Bar position controller
                barPosition = stage.builtin.controllers.PropertyController(bars, 'position', ...
                    @(state)surroundTrajectory(obj, state.time - obj.preTime*1e-3, k));
                p.addController(barPosition);
            end
            
            % Create the blank aperture.
            mask = stage.builtin.stimuli.Ellipse();
            mask.color = obj.backgroundIntensity;
            mask.radiusX = obj.apertureRadiusPix;
            mask.radiusY = obj.apertureRadiusPix;
            mask.position = obj.canvasSize / 2;
            p.addStimulus(mask);
            
            centerBar = stage.builtin.stimuli.Rectangle();
            centerBar.position = obj.canvasSize/2;
            centerBar.size = [obj.centerBarWidthPix obj.centerBarWidthPix*obj.numberOfCenterBars];
            centerBar.orientation = obj.centerBarOrientation;
            centerBar.color = obj.backgroundIntensity*obj.contrast+obj.backgroundIntensity;
            
            % Add the stimulus to the presentation.
            p.addStimulus(centerBar);

            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(centerBar, 'visible', ...
                @(state)state.time > (obj.preTime + obj.motionTime + obj.delayTime) * 1e-3 && state.time <= (obj.preTime + obj.motionTime + ceil(obj.stimDur*1e3) + obj.delayTime) * 1e-3);
            p.addController(spotVisible);

            % Bar position controller
            if ~isempty(strfind(obj.sequenceName, 'random'))
                barPosition = stage.builtin.controllers.PropertyController(centerBar, 'position', ...
                    @(state)randomTable(obj, state.time - (obj.preTime + obj.motionTime + obj.delayTime)*1e-3));
            elseif contains(obj.sequenceName, 'sequential180')
                barPosition = stage.builtin.controllers.PropertyController(centerBar, 'position', ...
                    @(state)motion180Table(obj, state.time - (obj.preTime + obj.motionTime + obj.delayTime)*1e-3));
            else
                barPosition = stage.builtin.controllers.PropertyController(centerBar, 'position', ...
                    @(state)motionTable(obj, state.time - (obj.preTime + obj.motionTime + obj.delayTime)*1e-3));
            end
            p.addController(barPosition);
            
            function p = motionTable(obj, time)
                % Calculate the increment with time.  
                inc = time * obj.speed + obj.startPosition;
                
                p = [cos(obj.centerBarOrientationRads) sin(obj.centerBarOrientationRads)] .* (inc*ones(1,2)) + obj.canvasSize/2;
            end
            
            function p = motion180Table(obj, time)
                % Calculate the increment with time.  
                inc = -obj.startPosition - time * obj.speed;
                
                p = [cos(obj.centerBarOrientationRads) sin(obj.centerBarOrientationRads)] .* (inc*ones(1,2)) + obj.canvasSize/2;
            end
            
            function p = randomTable(obj, time)
                if time >=0 && time <= obj.stimDur
                    frame = floor(obj.frameRate * time) + 1;
                    p = [cos(obj.centerBarOrientationRads) sin(obj.centerBarOrientationRads)] .* (obj.centerPositions(frame)*ones(1,2)) + obj.canvasSize/2;
                else
                    p = 5000*ones(1,2);
                end
            end

            
            % Surround bar position.
            function p = surroundTrajectory(obj, time, whichBar)
                if time > 0 && time <= obj.motionTime*1e-3
                    frame = floor(obj.frameRate * time) + 1;
                    p = [cos(obj.surroundBarOrientationRads) sin(obj.surroundBarOrientationRads)] .* (obj.positions(frame, whichBar)*ones(1,2)) + obj.canvasSize/2 - obj.thisCenterOffset;
                else
                    p = 5000*ones(1,2);
                end
            end
        end
  
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the center type.
            obj.sequenceName = obj.centerClasses{mod(floor(obj.numEpochsCompleted/length(obj.backgroundClasses)),length(obj.centerClasses))+1};
            
            % Get the background type.
            obj.backgroundClass = obj.backgroundClasses{mod(obj.numEpochsCompleted,length(obj.backgroundClasses))+1};
            
            % Get the delay time.
            obj.delayTime = obj.delayTimes(mod(floor(obj.numEpochsCompleted/length(obj.backgroundClasses)/length(obj.centerClasses)), length(obj.delayTimes))+1);
            epoch.addParameter('delayTime',obj.delayTime);
            
            % Get the spot contrast.
            obj.contrast = obj.contrasts(mod(floor(obj.numEpochsCompleted/length(obj.backgroundClasses)), length(obj.contrasts))+1);
            epoch.addParameter('contrast', obj.contrast);
            
            % Generate a random seed and seed the generator.
            obj.seed = RandStream.shuffleSeed;
            
            % Get the center bar positions.
            noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            barSeq = noiseStream.randperm(obj.numberOfCenterBars);
            if obj.centerFrameDwell > 1
                barSeq = ones(obj.centerFrameDwell,1)*barSeq;
                barSeq = barSeq(:)';
            end
            obj.centerPositions = [obj.startPosition + (barSeq-1)*obj.centerBarWidthPix 5000*ones(1,10)];
            
            % Get the surround bar positions.
            obj.noiseStream2 = RandStream('mt19937ar', 'Seed', obj.seed);
            % Get the bar positions for this epoch.
            obj.getBarPositions();
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('centerClass',obj.sequenceName);
            epoch.addParameter('backgroundClass',obj.backgroundClass);
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.motionTime + max([0, obj.delayTimes(:)']) + 250;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end