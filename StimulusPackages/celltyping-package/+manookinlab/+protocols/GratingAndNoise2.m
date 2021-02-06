classdef GratingAndNoise2 < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stim leading duration (ms)
        stimTime = 10000                % Stim duration (ms)
        tailTime = 250                  % Stim trailing duration (ms)
        randsPerRep = 7                 % Number of random seeds per repeat
        noiseContrast = 1/3             % Noise contrast (0-1)
        gratingContrast = 1.0           % Grating contrast (0-1)
        radius = 200                    % Inner radius in microns.
        apertureRadius = 250            % Aperture/blank radius in microns.
        barWidth = 60                   % Bar width (microns)
        backgroundSpeed = 1200          % Grating speed (microns/sec)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        backgroundSequences = 'drifting-jittering-stationary-nosurround' % Background sequence on alternating trials.
        noiseClass = 'gaussian'         % Noise type (binary or Gaussian)
        spatialClass = 'square'           % Grating spatial class
        onlineAnalysis = 'extracellular'% Online analysis type.
        numberOfAverages = uint16(120)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary','gaussian','uniform'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'square','sine'})
        backgroundSequencesType = symphonyui.core.PropertyType('char','row',{'drifting-jittering-stationary-nosurround','drifting-reversing-stationary-nosurround','drifting-jittering-reversing-stationary-nosurround','drifting-reversing-nosurround'})
        backgroundClasses
        seed
        noiseHi
        noiseLo
        frameSeq
        onsets
        stepSize
        surroundPhase
        noiseStream2
        backgroundClass
        temporalFrequency
        radiusPix
        apertureRadiusPix
        barWidthPix
        backgroundSpeedPix
        bgGratings
        gratingPositions
        thisCenterOffset
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
            obj.backgroundSpeedPix = obj.rig.getDevice('Stage').um2pix(obj.backgroundSpeed);
            
            % Get the center offset from Stage.
            obj.thisCenterOffset = obj.rig.getDevice('Stage').getCenterOffset();
            
            obj.stepSize = obj.backgroundSpeedPix / obj.frameRate;
            % Get the temporal frequency
            obj.temporalFrequency = obj.stepSize / (2 * obj.barWidthPix) * obj.frameRate;
            
            obj.getGratings();
            
            % Determine the sequence of backgrounds.
            %{'drifting-jittering-stationary','drifting-reversing-stationary','drifting-jittering','drifting-jittering-reversing-stationary','drifting-reversing'}
            switch obj.backgroundSequences
                case 'drifting-jittering-stationary-nosurround'
                    obj.backgroundClasses = {'drifting', 'jittering', 'stationary', 'nosurround'};
                case 'drifting-reversing-stationary-nosurround'
                    obj.backgroundClasses = {'drifting', 'reversing', 'stationary', 'nosurround'};
                case 'drifting-jittering-nosurround'
                    obj.backgroundClasses = {'drifting', 'jittering', 'nosurround'};
                case 'drifting-jittering-reversing-stationary-nosurround'
                    obj.backgroundClasses = {'drifting', 'jittering', 'reversing', 'stationary', 'nosurround'};
                case 'drifting-reversing-nosurround'
                    obj.backgroundClasses = {'drifting', 'reversing', 'nosurround'};
            end
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.TemporalNoiseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType', obj.onlineAnalysis, 'noiseClass', obj.noiseClass,...
                    'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                    'frameRate', obj.frameRate, 'numFrames', floor(obj.stimTime/1000 * obj.frameRate), 'frameDwell', 1, ...
                    'stdev', obj.noiseContrast*0.3, 'frequencyCutoff', 0, 'numberOfFilters', 0, ...
                    'correlation', 0, 'stimulusClass', 'Stage', ...
                    'groupBy','backgroundClass','groupByValues',obj.backgroundClasses);
                
                if length(obj.backgroundClasses) == 2
                    colors = [0 0 0; 0.8 0 0];
                else
                    colors = [0 0 0; 0.8 0 0; 0 0.5 0; 0 0 1];
                end
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',colors,...
                    'groupBy',{'backgroundClass'});
            end
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create the background grating.
            if strcmpi(obj.backgroundClass, 'reversing')
                bGrating = stage.builtin.stimuli.Grating(obj.spatialClass, 32); 
                bGrating.orientation = 0;
                bGrating.size = obj.canvasSize + [ceil(4*obj.barWidthPix) 0];
                bGrating.position = obj.canvasSize/2 - obj.thisCenterOffset;
                bGrating.spatialFreq = 1/(2*obj.barWidthPix); %convert from bar width to spatial freq
                bGrating.contrast = obj.gratingContrast;
                bGrating.color = 2*obj.backgroundIntensity;
                bGrating.phase = 0; 
                p.addStimulus(bGrating);
                
                % Make the grating visible only during the stimulus time.
                grate2Visible = stage.builtin.controllers.PropertyController(bGrating, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(grate2Visible);
            elseif ~strcmpi(obj.backgroundClass,'nosurround')
                bGrating = stage.builtin.stimuli.Image(obj.bgGratings);
                bGrating.position = obj.canvasSize/2 - obj.thisCenterOffset;
                bGrating.size = obj.canvasSize + [ceil(4*obj.barWidthPix) 0];
                bGrating.orientation = 0;

                % Set the minifying and magnifying functions.
                bGrating.setMinFunction(GL.NEAREST);
                bGrating.setMagFunction(GL.NEAREST);

                % Add the grating.
                p.addStimulus(bGrating);
                
                % Make the grating visible only during the stimulus time.
                grate2Visible = stage.builtin.controllers.PropertyController(bGrating, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(grate2Visible);
            end
            

            
            
            if strcmpi(obj.backgroundClass,'reversing')
                grateContrast = stage.builtin.controllers.PropertyController(bGrating, 'contrast', ...
                    @(state)surroundContrast(obj, state.time - obj.preTime * 1e-3));
                p.addController(grateContrast);
            elseif ~strcmpi(obj.backgroundClass,'stationary') && ~strcmpi(obj.backgroundClass,'nosurround')
                if strcmpi(obj.backgroundClass,'drifting')
                    bgController = stage.builtin.controllers.PropertyController(bGrating, 'position',...
                        @(state)surroundDrift(obj, state.time - obj.preTime * 1e-3));
                else
                    bgController = stage.builtin.controllers.PropertyController(bGrating, 'position',...
                        @(state)surroundTrajectory(obj, state.time - obj.preTime * 1e-3));
                end
                p.addController(bgController);
            end
            
            % Create the blank aperture.
            if obj.apertureRadiusPix > obj.radiusPix
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
            
            function c = getSpotAchromaticGaussian(obj, time)
                if time > 0 && time <= obj.stimTime*1e-3
                    c = obj.noiseContrast * 0.3 * obj.noiseHi.randn * obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    c = obj.backgroundIntensity;
                end
            end
            
            function c = getSpotAchromaticBinary(obj, time)
                if time > 0 && time <= obj.stimTime
                    c = obj.noiseContrast * (2*(obj.noiseHi.rand>0.5)-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    c = obj.backgroundIntensity;
                end
            end
            
            function c = getSpotAchromaticUniform(obj, time)
                if time > 0 && time <= obj.stimTime
                    c = obj.noiseContrast * (2*obj.noiseHi.rand-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    c = obj.backgroundIntensity;
                end
            end
            
            % Surround drift.
            function p = surroundDrift(obj, time)
                if time > 0 && time <= obj.stimTime
                    fr = floor(time*obj.frameRate)+1;
                    p = obj.gratingPositions(fr,:);
                else
                    p = obj.gratingPositions(1,:);
                end
            end
            
            % Surround trajectory
            function p = surroundTrajectory(obj, time)
                if time > 0 && time <= obj.stimTime
                    fr = floor(time*obj.frameRate)+1;
                    p = obj.gratingPositions(fr,:);
                else
                    p = obj.gratingPositions(1,:);
                end
            end
            
            % Surround contrast
            function c = surroundContrast(obj, time)
                if time > 0 && time <= obj.stimTime
                    c = obj.gratingContrast * sin(time*2*pi*obj.temporalFrequency);
                else
                    c = obj.gratingContrast; 
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
            obj.noiseStream2 = RandStream('mt19937ar', 'Seed', obj.seed+1781);
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('temporalFrequency',obj.temporalFrequency);
            epoch.addParameter('backgroundClass',obj.backgroundClass);
            
            % Set the surround phase.
            obj.surroundPhase = 0;
            
            numFrames = ceil(obj.stimTime * 1e-3 * obj.frameRate) + 15;
            
            %{'drifting', 'jittering', 'reversing', 'stationary'};
            numPositions = floor(obj.frameRate/obj.temporalFrequency);
            switch obj.backgroundClass
                case 'drifting'
                    obj.gratingPositions = 0 : numFrames-1;
                    obj.gratingPositions = mod(obj.gratingPositions, numPositions);
                case 'jittering'
                    obj.gratingPositions = 2*(obj.noiseStream2.rand(1,numFrames)>0.5) - 1;
                    obj.gratingPositions = mod(cumsum(obj.gratingPositions), numPositions);
                case 'reversing'
                    obj.gratingPositions = zeros(1,numFrames);
                case {'stationary','nosurround'}
                    obj.gratingPositions = zeros(1,numFrames);
            end
            obj.gratingPositions = obj.gratingPositions(:);
            obj.gratingPositions = [obj.gratingPositions*obj.stepSize zeros(size(obj.gratingPositions,1),1)] + ones(size(obj.gratingPositions,1),1)*(obj.canvasSize/2 - obj.thisCenterOffset);
        end
        
        % Pre-generate the gratings.
        function getGratings(obj)
            downsamp = 4;
            sz = ceil(sqrt(obj.canvasSize(1)^2 + obj.canvasSize(2)^2));
            x = linspace(-sz/2, sz/2, sz/downsamp);
            
            x = x / (obj.barWidthPix*2) * 2 * pi;
            obj.bgGratings = sin(x);
            
%             numGratings = 1; %floor(obj.frameRate/obj.temporalFrequency);
%             
%             obj.bgGratings = zeros(length(x),numGratings);
%             
%             shiftPerFrame = obj.temporalFrequency/obj.frameRate*2*pi;
%             for k = 1 : numGratings
%                 obj.bgGratings(:,k) = sin((x*2*pi / obj.barWidthPix/2) + (k-1)*shiftPerFrame);
%             end
            
            if strcmp(obj.spatialClass, 'square')
                obj.bgGratings = sign(obj.bgGratings);
            end
        
            % Convert to pixel values.
            obj.bgGratings = obj.backgroundIntensity * (obj.gratingContrast*obj.bgGratings) + obj.backgroundIntensity;
            obj.bgGratings = uint8(255 * obj.bgGratings);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end