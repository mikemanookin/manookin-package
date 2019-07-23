classdef GratingAndNoise2 < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stim leading duration (ms)
        stimTime = 10000                % Stim duration (ms)
        tailTime = 250                  % Stim trailing duration (ms)
        randsPerRep = 6                 % Number of random seeds per repeat
        noiseContrast = 1/3             % Noise contrast (0-1)
        gratingContrast = 1.0           % Grating contrast (0-1)
        radius = 200                    % Inner radius in microns.
        apertureRadius = 250            % Aperture/blank radius in microns.
        barWidth = 60                   % Bar width (microns)
        backgroundSpeed = 750           % Grating speed (microns/sec)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        backgroundSequences = 'drifting-jittering-stationary' % Background sequence on alternating trials.
        noiseClass = 'gaussian'         % Noise type (binary or Gaussian)
        spatialClass = 'square'           % Grating spatial class
        onlineAnalysis = 'extracellular'% Online analysis type.
        numberOfAverages = uint16(48)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary','gaussian','uniform'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'square','sine'})
        backgroundSequencesType = symphonyui.core.PropertyType('char','row',{'drifting-jittering-stationary','drifting-reversing-stationary','drifting-jittering','drifting-jittering-reversing-stationary','drifting-reversing'})
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
            obj.backgroundSpeedPix = obj.rig.getDevice('Stage').um2pix(obj.backgroundSpeed);
            
            obj.stepSize = obj.backgroundSpeedPix / obj.frameRate;
            % Get the temporal frequency
            obj.temporalFrequency = obj.stepSize / (2 * obj.barWidthPix) * obj.frameRate;
            
            % Determine the sequence of backgrounds.
            %{'drifting-jittering-stationary','drifting-reversing-stationary','drifting-jittering','drifting-jittering-reversing-stationary','drifting-reversing'}
            switch obj.backgroundSequences
                case 'drifting-jittering-stationary'
                    obj.backgroundClasses = {'drifting', 'jittering', 'stationary'};
                case 'drifting-reversing-stationary'
                    obj.backgroundClasses = {'drifting', 'reversing', 'stationary'};
                case 'drifting-jittering'
                    obj.backgroundClasses = {'drifting', 'jittering'};
                case 'drifting-jittering-reversing-stationary'
                    obj.backgroundClasses = {'drifting', 'jittering', 'reversing', 'stationary'};
                case 'drifting-reversing'
                    obj.backgroundClasses = {'drifting', 'reversing'};
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
                    colors = [0 0 0; 0.8 0 0; 0 0.5 0];
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
            
            % Create the background.
            bGrating = stage.builtin.stimuli.Grating(obj.spatialClass, 16); 
            bGrating.orientation = 0;
            bGrating.size = max(obj.canvasSize) * ones(1,2);
            bGrating.position = obj.canvasSize/2;
            bGrating.spatialFreq = 1/(2*obj.barWidthPix); %convert from bar width to spatial freq
            bGrating.contrast = obj.gratingContrast;
            bGrating.color = 2*obj.backgroundIntensity;
            bGrating.phase = obj.surroundPhase; 
            p.addStimulus(bGrating);

            % Make the grating visible only during the stimulus time.
            grate2Visible = stage.builtin.controllers.PropertyController(bGrating, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(grate2Visible);
            
            if strcmpi(obj.backgroundClass,'reversing')
                grateContrast = stage.builtin.controllers.PropertyController(bGrating, 'contrast', ...
                    @(state)surroundContrast(obj, state.time - obj.preTime * 1e-3));
                p.addController(grateContrast);
            elseif ~strcmpi(obj.backgroundClass,'stationary')
                if strcmpi(obj.backgroundClass,'drifting')
                    bgController = stage.builtin.controllers.PropertyController(bGrating, 'phase',...
                        @(state)surroundDrift(obj, state.time - obj.preTime * 1e-3));
                else
                    bgController = stage.builtin.controllers.PropertyController(bGrating, 'phase',...
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
                    p = 2*pi * obj.stepSize / (2*obj.barWidthPix);
                else
                    p = 0;
                end
                obj.surroundPhase = obj.surroundPhase + p;
                p = obj.surroundPhase*180/pi;
            end
            
            % Surround trajectory
            function p = surroundTrajectory(obj, time)
                if time > 0 && time <= obj.stimTime
                    p = obj.noiseStream2.randn*2*pi * obj.stepSize / (2*obj.barWidthPix);
                else
                    p = 0;
                end
                obj.surroundPhase = obj.surroundPhase + p;
                p = obj.surroundPhase*180/pi;
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
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end