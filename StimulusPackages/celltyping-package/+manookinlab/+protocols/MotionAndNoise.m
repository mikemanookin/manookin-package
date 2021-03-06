classdef MotionAndNoise < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stim leading duration (ms)
        stimTime = 10000                % Stim duration (ms)
        tailTime = 250                  % Stim trailing duration (ms)
        randsPerRep = 8                 % Number of random seeds per repeat
        noiseContrast = 1/3             % Noise contrast (0-1)
        radius = 200                    % Inner radius in microns.
        apertureRadius = 250            % Aperture/blank radius in microns.
        frameDwell = 1                  % Number of frames to present each unique spot contrast
        numBarPairs = 2                 % Number of bar pairs (positive/negative contrast)
        barFrameDwell = 2               % Frame dwell for background bars
        barWidth = 50                   % Bar width (microns)
        barContrast = 1.0               % Bar contrast (-1 : 1)
        barOrientation = 90              % Bar orientation (degrees)
        backgroundIntensity = 0.5       % Background light intensity (0-1) 
        backgroundSequences = 'sequential-random-stationary' % Background sequence on alternating trials.
        noiseClass = 'gaussian'         % Noise type (binary or Gaussian)
        chromaticClass = 'achromatic'   % Chromatic class
        onlineAnalysis = 'extracellular'% Online analysis type.
        numberOfAverages = uint16(120)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary','gaussian','uniform'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        backgroundSequencesType = symphonyui.core.PropertyType('char','row',{'sequential-random','sequential-random-stationary'})
        seed
        noiseHi
        noiseLo
        frameSeq
        onsets
        noiseStream2
        orientationRads
        thisCenterOffset
        positions
        radiusPix
        apertureRadiusPix
        barWidthPix
        backgroundClasses
        backgroundClass
        numBars
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            if strcmp(obj.onlineAnalysis,'extracellular')
                obj.showFigure('manookinlab.figures.AutocorrelationFigure', obj.rig.getDevice(obj.amp));
            end
            
            obj.radiusPix = obj.rig.getDevice('Stage').um2pix(obj.radius);
            obj.apertureRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.apertureRadius);
            obj.barWidthPix = obj.rig.getDevice('Stage').um2pix(obj.barWidth);
            
            obj.numBars = round(obj.numBarPairs * 2);
            % Calculate the orientation in radians.
            obj.orientationRads = obj.barOrientation/180*pi;
            
            switch obj.backgroundSequences
                case 'sequential-random-stationary'
                    obj.backgroundClasses = {'sequential','random','stationary'};
                case 'sequential-random'
                    obj.backgroundClasses = {'sequential','random'};
            end

            % Get the center offset from Stage.
            obj.thisCenterOffset = obj.rig.getDevice('Stage').getCenterOffset();
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.TemporalNoiseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType', obj.onlineAnalysis, 'noiseClass', obj.noiseClass,...
                    'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                    'frameRate', obj.frameRate, 'numFrames', floor(obj.stimTime*1e-3 * obj.frameRate / obj.frameDwell), 'frameDwell', obj.frameDwell, ...
                    'stdev', obj.noiseContrast*0.3, 'frequencyCutoff', 0, 'numberOfFilters', 0, ...
                    'correlation', 0, 'stimulusClass', 'Stage', ...
                    'groupBy','backgroundClass','groupByValues',obj.backgroundClasses);
                
                
                if length(obj.backgroundClasses) == 2
                    colors = [0 0 0; 0.8 0 0];
                else
                    colors = [0 0 0; 0.8 0 0; 0 0.5 0];
                end
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',colors,...
                    'groupBy',{'backgroundClass'});
            end
        end
        
        function getBarPositions(obj)
            % Calculate the number of frames.
            numFrames = obj.stimTime*1e-3*obj.frameRate + 16;
            % Calculate the number of positions.
            numPositions = floor(min(obj.canvasSize) / obj.barWidthPix);
            positionValues = linspace(-min(obj.canvasSize)/2+obj.barWidthPix/2,min(obj.canvasSize)/2-obj.barWidthPix/2,numPositions);
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
            
            if obj.barFrameDwell > 1
                nUniquePts = ceil(numFrames / obj.barFrameDwell);
                tmp = ones(obj.barFrameDwell,1) * barSeq(1:nUniquePts)';
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
                bars.size = [obj.barWidthPix max(obj.canvasSize)];
                bars.orientation = obj.barOrientation;
                % Convert from contrast to intensity.
                if obj.backgroundIntensity > 0
                    bars.color = obj.backgroundIntensity*barSign*obj.barContrast+obj.backgroundIntensity;
                else
                    bars.color = obj.barContrast;
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
            if obj.apertureRadius > obj.radius
                mask = stage.builtin.stimuli.Ellipse();
                mask.color = obj.backgroundIntensity;
                mask.radiusX = obj.apertureRadiusPix;
                mask.radiusY = obj.apertureRadiusPix;
                mask.position = obj.canvasSize / 2;
                p.addStimulus(mask);
            end
            
            spot = stage.builtin.stimuli.Ellipse();
            spot.radiusX = obj.radiusPix;
            spot.radiusY = obj.radiusPix; 
            spot.position = obj.canvasSize/2;
            spot.color = obj.backgroundIntensity;
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            % Control the spot color.
            if strcmpi(obj.noiseClass, 'gaussian')
                colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                    @(state)getSpotAchromaticGaussian(obj, state.time - obj.preTime * 1e-3));
            elseif strcmpi(obj.noiseClass, 'binary')
                colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                    @(state)getSpotAchromaticBinary(obj, state.time - obj.preTime * 1e-3));
            else
                colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                    @(state)getSpotAchromaticUniform(obj, state.time - obj.preTime * 1e-3));
            end
            p.addController(colorController);
            
            
            cont = obj.backgroundIntensity;
            function c = getSpotAchromaticGaussian(obj, time)
                frame = floor(obj.frameRate * time);
                if time > 0 && time <= obj.stimTime
                    if mod(frame,obj.frameDwell) == 0
                        cont = obj.noiseContrast * 0.3 * obj.noiseHi.randn * obj.backgroundIntensity + obj.backgroundIntensity;
                    end
                    c = cont;
                else
                    c = obj.backgroundIntensity;
                end
            end
            
            function c = getSpotAchromaticBinary(obj, time)
                frame = floor(obj.frameRate * time);
                if time > 0 && time <= obj.stimTime
                    if mod(frame,obj.frameDwell) == 0
                        cont = obj.noiseContrast * (2*(obj.noiseHi.rand>0.5)-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                    end
                    c = cont;
                else
                    c = obj.backgroundIntensity;
                end
            end
            
            function c = getSpotAchromaticUniform(obj, time)
                frame = floor(obj.frameRate * time);
                if time > 0 && time <= obj.stimTime
                    if mod(frame,obj.frameDwell) == 0
                        cont = obj.noiseContrast * (2*obj.noiseHi.rand-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                    end
                    c = cont;
                else
                    c = obj.backgroundIntensity;
                end
            end
            
            % Surround bar position.
            function p = surroundTrajectory(obj, time, whichBar)
                if time > 0 && time <= obj.stimTime
                    frame = floor(obj.frameRate * time) + 1;
                    p = [cos(obj.orientationRads) sin(obj.orientationRads)] .* (obj.positions(frame, whichBar)*ones(1,2)) + obj.canvasSize/2 - obj.thisCenterOffset;
                else
                    p = 5000*ones(1,2);
                end
            end
        end
  
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the background type.
            obj.backgroundClass = obj.backgroundClasses{mod(obj.numEpochsCompleted,length(obj.backgroundClasses))+1};
            
            % Deal with the seed.
            if obj.randsPerRep == 0
                obj.seed = 1;
            elseif obj.randsPerRep > 0 && (mod(floor(obj.numEpochsCompleted/length(obj.backgroundClasses))+1,obj.randsPerRep+1) == 0)
                obj.seed = 1;
            else
                obj.seed = RandStream.shuffleSeed;
            end
            
            % Seed the random number generators.
            obj.noiseHi = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.noiseStream2 = RandStream('mt19937ar', 'Seed', obj.seed);
            % Get the bar positions for this epoch.
            obj.getBarPositions();
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('backgroundClass',obj.backgroundClass);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end