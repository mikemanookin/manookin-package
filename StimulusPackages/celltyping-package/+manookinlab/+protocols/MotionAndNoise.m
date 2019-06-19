classdef MotionAndNoise < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stim leading duration (ms)
        stimTime = 10000                % Stim duration (ms)
        tailTime = 250                  % Stim trailing duration (ms)
        randsPerRep = 10                 % Number of random seeds per repeat
        noiseContrast = 1/3             % Noise contrast (0-1)
        radius = 200                    % Inner radius in microns.
        apertureRadius = 250            % Aperture/blank radius in microns.
        barWidth = 50                   % Bar width (microns)
        barContrast = 1.0               % Bar contrast (-1 : 1)
        barOrientation = 0              % Bar orientation (degrees)
        backgroundIntensity = 0.5       % Background light intensity (0-1) 
        noiseClass = 'gaussian'         % Noise type (binary or Gaussian)
        chromaticClass = 'achromatic'   % Chromatic class
        onlineAnalysis = 'extracellular'% Online analysis type.
        numberOfAverages = uint16(100)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary','gaussian','uniform'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        backgroundClassType = symphonyui.core.PropertyType('char', 'row', {'jittering','drifting'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'square','sine'})
        seed
        noiseHi
        noiseLo
        frameSeq
        onsets
        noiseStream2
        orientationRads
        thisCenterOffset
        positions
        halfFrames
        radiusPix
        apertureRadiusPix
        barWidthPix
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            obj.radiusPix = obj.rig.getDevice('Stage').um2pix(obj.radius);
            obj.apertureRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.apertureRadius);
            obj.barWidthPix = obj.rig.getDevice('Stage').um2pix(obj.barWidth);
            
            % Calculate the period durations.
            halfTime = floor(obj.stimTime/2);
            obj.onsets = cumsum([1 halfTime])*1e-3;
            % Calculate the number of frames in each sequence.
            obj.halfFrames = floor(obj.stimTime/2*1e-3*obj.frameRate);
            
            % Calculate the orientation in radians.
            obj.orientationRads = obj.barOrientation/180*pi;
            
            % Get the center offset from Stage.
            obj.thisCenterOffset = obj.rig.getDevice('Stage').getCenterOffset();
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.TemporalNoiseFigure2', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'noiseClass',obj.noiseClass,...
                    'preTime',obj.preTime,...
                    'frameRate',obj.frameRate,...
                    'onsets',obj.onsets,...
                    'durations',halfTime*ones(1,2)*1e-3,...
                    'contrasts',[obj.noiseContrast obj.noiseContrast]);
            end
        end
        
        function getBarPositions(obj)
            % Calculate the number of frames.
            numFrames = 2*obj.halfFrames + 15;
            % Calculate the number of positions.
            numPositions = floor(min(obj.canvasSize) / obj.barWidth);
            positionValues = linspace(-min(obj.canvasSize)/2+obj.barWidth/2,min(obj.canvasSize)/2-obj.barWidth/2,numPositions);
            positionValues = positionValues(:);
            
            % Get the random sequence.
            numCycles = ceil(obj.halfFrames / numPositions);
            randSeq = zeros(numCycles*numPositions,1);
            for k = 1 : numCycles
                idx = (k-1)*numPositions + (1 : numPositions);
                randSeq(idx) = obj.noiseStream2.randperm(numPositions);
            end
            randSeq = randSeq(1 : obj.halfFrames);
%             randSeq = ceil(obj.noiseStream2.rand(1,obj.halfFrames)*numPositions);
%             randSeq(randSeq < 1) = 1;
            
            % Get the position values for the motion sequence.
            barSeq = ones(numFrames,1);
            % Motion sequence
            barSeq(1 : obj.halfFrames) = mod(0:obj.halfFrames-1,numPositions)' + 1;
            barSeq(obj.halfFrames + 1 : obj.halfFrames*2) = randSeq;
            obj.positions = [positionValues(barSeq) zeros(size(barSeq))];
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create the stimulus.
            bars = stage.builtin.stimuli.Rectangle();
            bars.position = obj.canvasSize/2 - obj.thisCenterOffset;
            bars.size = [obj.barWidth max(obj.canvasSize)];
            bars.orientation = obj.barOrientation;
            % Convert from contrast to intensity.
            if obj.backgroundIntensity > 0
                bars.color = obj.backgroundIntensity*obj.barContrast+obj.backgroundIntensity;
            else
                bars.color = obj.contrast;
            end

            % Add the stimulus to the presentation.
            p.addStimulus(bars);

            % Make the bars visible only during the stimulus time.
            gridVisible = stage.builtin.controllers.PropertyController(bars, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(gridVisible);
            
            % Bar position controller
            barPosition = stage.builtin.controllers.PropertyController(bars, 'position', ...
                @(state)surroundTrajectory(obj, state.time - obj.preTime*1e-3));
            p.addController(barPosition);
            
            % Create the blank aperture.
            if obj.apertureRadius > obj.radius
                mask = stage.builtin.stimuli.Ellipse();
                mask.color = obj.backgroundIntensity;
                mask.radiusX = obj.apertureRadius;
                mask.radiusY = obj.apertureRadius;
                mask.position = obj.canvasSize / 2;
                p.addStimulus(mask);
            end
            
            spot = stage.builtin.stimuli.Ellipse();
            spot.radiusX = obj.radius;
            spot.radiusY = obj.radius; 
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
            
            function c = getSpotAchromaticGaussian(obj, time)
                if time >= obj.onsets(1) && time < obj.onsets(2)
                    c = obj.noiseContrast * 0.3 * obj.noiseHi.randn * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(2) && time <= obj.stimTime*1e-3
                    c = obj.noiseContrast * 0.3 * obj.noiseLo.randn * obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    c = obj.backgroundIntensity;
                end
            end
            
            function c = getSpotAchromaticBinary(obj, time)
                if time >= obj.onsets(1) && time < obj.onsets(2)
                    c = obj.noiseContrast * (2*(obj.noiseHi.rand>0.5)-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(2) && time <= obj.stimTime*1e-3
                    c = obj.noiseContrast * (2*(obj.noiseLo.rand>0.5)-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    c = obj.backgroundIntensity;
                end
            end
            
            function c = getSpotAchromaticUniform(obj, time)
                if time >= obj.onsets(1) && time < obj.onsets(2)
                    c = obj.noiseContrast * (2*obj.noiseHi.rand-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(2) && time <= obj.stimTime*1e-3
                    c = obj.noiseContrast * (2*obj.noiseLo.rand-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    c = obj.backgroundIntensity;
                end
            end
            
            % Surround bar position.
            function p = surroundTrajectory(obj, time)
                if time >=0 && time <= obj.stimTime
                    frame = floor(obj.frameRate * time) + 1;
                    p = [cos(obj.orientationRads) sin(obj.orientationRads)] .* (obj.positions(frame)*ones(1,2)) + obj.canvasSize/2 - obj.thisCenterOffset;
                else
                    p = 5000*ones(1,2);
                end
            end
        end
  
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Deal with the seed.
            if obj.randsPerRep > 0 && (mod(obj.numEpochsCompleted+1,obj.randsPerRep+1) == 0)
                obj.seed = 1;
            else
                obj.seed = RandStream.shuffleSeed;
            end
            
            % Seed the random number generators.
            obj.noiseHi = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.noiseLo = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.noiseStream2 = RandStream('mt19937ar', 'Seed', obj.seed);
            % Get the bar positions for this epoch.
            obj.getBarPositions();
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('onsets',obj.onsets);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end