classdef AdaptNoiseMovingBackground < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stim leading duration (ms)
        stimTime = 20000                % Stim duration (ms)
        tailTime = 250                  % Stim trailing duration (ms)
        repTime = 3500                  % Repeat period durations (ms)
        spotContrast = 1.0              % High contrast (0-1)
        gratingContrast = 0.5           % Low contrast (0-1)
        barWidth = 75                   % Bar width (pixels)
        backgroundSpeed = 750           % Grating jitter/frame (pix/sec)
        radius = 100                    % Inner radius in pixels.
        apertureRadius = 150            % Aperture/blank radius in pixels.
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        noiseClass = 'gaussian'         % Noise type (binary or Gaussian)
        backgroundClass = 'drifting'    % Stimulus class
        chromaticClass = 'achromatic'   % Chromatic class
        onlineAnalysis = 'extracellular'% Online analysis type.
        numberOfAverages = uint16(35)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary','gaussian','uniform'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        backgroundClassType = symphonyui.core.PropertyType('char', 'row', {'jittering','drifting'})
        seed
        noiseHi
        noiseHiRep
        noiseLo
        noiseLoRep
        noiseStream2
        frameSeq
        onsets
        stepSize
        surroundPhase
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            % Calculate the period durations.
            halfTime = floor(obj.stimTime/2);
            randTime = halfTime - obj.repTime;
            obj.onsets = cumsum([1 randTime obj.repTime randTime])*1e-3;
            
            obj.stepSize = obj.backgroundSpeed / obj.frameRate;
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.TemporalNoiseFigure2', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'noiseClass',obj.noiseClass,...
                    'preTime',obj.preTime,...
                    'frameRate',obj.frameRate,...
                    'onsets',obj.onsets([1 3]),...
                    'durations',randTime*ones(1,2)*1e-3,...
                    'contrasts',obj.spotContrast*ones(1,2));
            end
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create the background.
            bGrating = stage.builtin.stimuli.Grating('square'); 
            bGrating.orientation = 0;
            bGrating.size = max(obj.canvasSize) * ones(1,2);
            bGrating.position = obj.canvasSize/2 + obj.centerOffset;
            bGrating.spatialFreq = 1/(2*obj.barWidth); %convert from bar width to spatial freq
            bGrating.contrast = obj.gratingContrast;
            bGrating.color = 2*obj.backgroundIntensity;
            bGrating.phase = obj.surroundPhase; 
            p.addStimulus(bGrating);

            % Make the grating visible only during the stimulus time.
            grate2Visible = stage.builtin.controllers.PropertyController(bGrating, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(grate2Visible);

            if strcmpi(obj.backgroundClass,'drifting')
                bgController = stage.builtin.controllers.PropertyController(bGrating, 'phase',...
                    @(state)surroundDrift(obj, state.time - obj.preTime * 1e-3));
            else
                bgController = stage.builtin.controllers.PropertyController(bGrating, 'phase',...
                    @(state)surroundTrajectory(obj, state.time - obj.preTime * 1e-3));
            end
            p.addController(bgController);
            
            % Create the blank aperture.
            if obj.apertureRadius > obj.radius
                mask = stage.builtin.stimuli.Ellipse();
                mask.color = obj.backgroundIntensity;
                mask.radiusX = obj.apertureRadius;
                mask.radiusY = obj.apertureRadius;
                mask.position = obj.canvasSize / 2 + obj.centerOffset;
                p.addStimulus(mask);
            end
            
            % Create the spot.
            spot = stage.builtin.stimuli.Ellipse();
            spot.radiusX = obj.radius;
            spot.radiusY = obj.radius; 
            spot.position = obj.canvasSize/2 + obj.centerOffset;
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
                    c = obj.spotContrast * 0.3 * obj.noiseHi.randn * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(2) && time < obj.onsets(3)
                    c = obj.spotContrast * 0.3 * obj.noiseHiRep.randn * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(3) && time < obj.onsets(4)
                    c = obj.spotContrast * 0.3 * obj.noiseLo.randn * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(4) && time <= obj.stimTime*1e-3
                    c = obj.spotContrast * 0.3 * obj.noiseLoRep.randn * obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    c = obj.backgroundIntensity;
                end
            end
            
            function c = getSpotAchromaticBinary(obj, time)
                if time >= obj.onsets(1) && time < obj.onsets(2)
                    c = obj.spotContrast * (2*(obj.noiseHi.rand>0.5)-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(2) && time < obj.onsets(3)
                    c = obj.spotContrast * (2*(obj.noiseHiRep.rand>0.5)-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(3) && time < obj.onsets(4)
                    c = obj.spotContrast * (2*(obj.noiseLo.rand>0.5)-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(4) && time <= obj.stimTime*1e-3
                    c = obj.spotContrast * (2*(obj.noiseLoRep.rand>0.5)-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    c = obj.backgroundIntensity;
                end
            end
            
            function c = getSpotAchromaticUniform(obj, time)
                if time >= obj.onsets(1) && time < obj.onsets(2)
                    c = obj.spotContrast * (2*obj.noiseHi.rand-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(2) && time < obj.onsets(3)
                    c = obj.spotContrast * (2*obj.noiseHiRep.rand-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(3) && time < obj.onsets(4)
                    c = obj.spotContrast * (2*obj.noiseLo.rand-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(4) && time <= obj.stimTime*1e-3
                    c = obj.spotContrast * (2*obj.noiseLoRep.rand-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    c = obj.backgroundIntensity;
                end
            end
            
            % Surround drift.
            function p = surroundDrift(obj, time)
                if time > 0 && time < obj.onsets(3)
                    p = 2*pi * obj.stepSize / obj.barWidth;
                else
                    p = 0;
                end
                obj.surroundPhase = obj.surroundPhase + p;
                p = obj.surroundPhase*180/pi;
            end
            
            % Surround trajectory
            function p = surroundTrajectory(obj, time)
                if time > 0 && time < obj.onsets(3)
                    p = obj.noiseStream2.randn*2*pi * obj.stepSize / obj.barWidth;
                else
                    p = 0;
                end
                obj.surroundPhase = obj.surroundPhase + p;
                p = obj.surroundPhase*180/pi;
            end
        end
  
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Deal with the seed.
            obj.seed = RandStream.shuffleSeed;
            
            % Seed the random number generators.
            obj.noiseHi = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.noiseHiRep = RandStream('mt19937ar', 'Seed', 1);
            obj.noiseLo = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.noiseLoRep = RandStream('mt19937ar', 'Seed', 1);
            obj.noiseStream2 = RandStream('mt19937ar', 'Seed', obj.seed+1781);
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('onsets',obj.onsets);
            
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