classdef AdaptNoiseInterleaved < edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stim leading duration (ms)
        stimTime = 21000                % Stim duration (ms)
        tailTime = 250                  % Stim trailing duration (ms)
        repTime = 3500                  % Repeat period durations (ms)
        highContrast = 1.0              % High contrast (0-1)
        lowContrast = 1/3               % Low contrast (0-1)
        radius = 100                    % Inner radius in pixels.
        apertureRadius = 150            % Aperture/blank radius in pixels.
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        noiseClass = 'gaussian'  % Noise type (binary or Gaussian)
        stimulusClass = 'spot' % Stimulus class
        chromaticClass = 'achromatic'   % Chromatic class
        onlineAnalysis = 'extracellular'% Online analysis type.
        numberOfAverages = uint16(20)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary','gaussian'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'spot','annulus', 'full-field'})
        seed
        noiseHi
        noiseHiRep
        noiseLo
        noiseLoRep
        frameSeq
        onsets
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.manookin.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',[30 144 255]/255,...
                'groupBy',{'frameRate'});
            
            % Calculate the period durations.
            halfTime = floor(obj.stimTime/2);
            randTime = halfTime - obj.repTime;
            obj.onsets = cumsum([1 randTime obj.repTime randTime])*1e-3;
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            if strcmp(obj.stimulusClass, 'spot')
                spot = stage.builtin.stimuli.Ellipse();
                spot.radiusX = obj.radius;
                spot.radiusY = obj.radius; 
                spot.position = obj.canvasSize/2 + obj.centerOffset;
            else
                spot = stage.builtin.stimuli.Rectangle();
                spot.size = obj.canvasSize;
                spot.position = obj.canvasSize/2;
                spot.orientation = 0;
            end
            spot.color = obj.backgroundIntensity;
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Add a center mask if it's an annulus.
            if strcmp(obj.stimulusClass, 'annulus')
                mask = stage.builtin.stimuli.Ellipse();
                mask.radiusX = obj.apertureRadius;
                mask.radiusY = obj.apertureRadius;
                mask.position = obj.canvasSize/2 + obj.centerOffset;
                mask.color = obj.backgroundIntensity; 
                p.addStimulus(mask);
            end
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            % Control the spot color.
            if strcmpi(obj.noiseClass, 'gaussian')
                colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                    @(state)getSpotAchromaticGaussian(obj, state.time - obj.preTime * 1e-3));
            else
                colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                    @(state)getSpotAchromaticBinary(obj, state.time - obj.preTime * 1e-3));
            end
            p.addController(colorController);
            
            function c = getSpotAchromaticGaussian(obj, time)
                if time >= obj.onsets(1) && time < obj.onsets(2)
                    c = obj.highContrast * 0.3 * obj.noiseHi.randn * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(2) && time < obj.onsets(3)
                    c = obj.highContrast * 0.3 * obj.noiseHiRep.randn * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(3) && time < obj.onsets(4)
                    c = obj.lowContrast * 0.3 * obj.noiseLo.randn * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(4) && time <= obj.stimTime*1e-3
                    c = obj.lowContrast * 0.3 * obj.noiseLoRep.randn * obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    c = obj.backgroundIntensity;
                end
            end
            
            function c = getSpotAchromaticBinary(obj, time)
                if time >= obj.onsets(1) && time < obj.onsets(2)
                    c = obj.highContrast * (2*obj.noiseHi.rand-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(2) && time < obj.onsets(3)
                    c = obj.highContrast * (2*obj.noiseHiRep.rand-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(3) && time < obj.onsets(4)
                    c = obj.lowContrast * (2*obj.noiseLo.rand-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                elseif time >= obj.onsets(4) && time <= obj.stimTime*1e-3
                    c = obj.lowContrast * (2*obj.noiseLoRep.randn-1) * obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    c = obj.backgroundIntensity;
                end
            end
        end
  
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Deal with the seed.
            obj.seed = RandStream.shuffleSeed;
            
            % Seed the random number generators.
            obj.noiseHi = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.noiseHiRep = RandStream('mt19937ar', 'Seed', 1);
            obj.noiseLo = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.noiseLoRep = RandStream('mt19937ar', 'Seed', 1);
            
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