classdef LedChirp < edu.washington.riekelab.protocols.RiekeLabProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Stimulus leading duration (ms)
        tailTime = 500                  % Stimulus trailing duration (ms)
        stepTime = 500                  % Step duration (ms)
        frequencyTime = 10000           % Frequency sweep duration (ms)
        contrastTime = 8000             % Contrast sweep duration (ms)
        interTime = 1000                % Duration between stimuli (ms)
        stepContrast = 1.0              % Step contrast (0 - 1)
        frequencyContrast = 1.0         % Contrast during frequency sweep (0-1)
        radius = 200                    % Radius in pixels.
        frequencyMin = 0.0              % Minimum temporal frequency (Hz)
        frequencyMax = 10.0             % Maximum temporal frequency (Hz)
        contrastMin = 0.02              % Minimum contrast (0-1)
        contrastMax = 1.0               % Maximum contrast (0-1)
        contrastFrequency = 2.0         % Temporal frequency of contrast sweep (Hz)
        stimulusClass = 'spot'          % Stimulus class
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular'         % Online analysis type.
        numberOfAverages = uint16(5)   % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'spot','annulus', 'full-field'})
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            if strcmp(obj.stimulusClass, 'spot')
                spot = stage.builtin.stimuli.Ellipse();
                spot.radiusX = obj.radius;
                spot.radiusY = obj.radius; 
                spot.position = obj.canvasSize/2;
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
                mask.radiusX = obj.radius;
                mask.radiusY = obj.radius;
                mask.position = obj.canvasSize/2;
                mask.color = obj.backgroundIntensity; 
                p.addStimulus(mask);
            end
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            frequencyDelta = (obj.frequencyMax - obj.frequencyMin)/(obj.frequencyTime*1e-3);
            contrastDelta = (obj.contrastMax - obj.contrastMin)/(obj.contrastTime*1e-3);
            
%             numFrames = ceil(obj.stimTime*1e-3*obj.frameRate);
%             chirpFrames = zeros(1,numFrames);
%             freqT = 1/obj.frameRate : 1/obj.frameRate : obj.frequencyTime*1e-3;
%             freqChange = linspace(obj.frequencyMin, obj.frequencyMax, length(freqT));
%             freqPhase = cumsum(freqChange/obj.frameRate);
%             sin(2*pi*(obj.frequencyMin*t+frequencyDelta*t.^2))
            
            % Control the spot color.
            colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                @(state)getSpotColor(obj, state.time - obj.preTime * 1e-3));
            p.addController(colorController);
            
            function c = getSpotColor(obj, time)
                if time > 0 && time <= obj.stepTime*1e-3
                    v = obj.stepContrast;
                elseif time > (obj.stepTime+obj.interTime)*1e-3 && time <= (2*obj.stepTime+obj.interTime)*1e-3
                    v = -obj.stepContrast;
                elseif time > (2*obj.stepTime+2*obj.interTime)*1e-3 && time <= (2*obj.stepTime+2*obj.interTime+obj.frequencyTime)*1e-3
                    t = time - (2*obj.stepTime+2*obj.interTime)*1e-3;
                    v = obj.frequencyContrast*sin(2*pi*(obj.frequencyMin*t+frequencyDelta*t.^2));
                elseif time > (2*obj.stepTime+3*obj.interTime+obj.frequencyTime)*1e-3 && time <= obj.stimTime*1e-3
                    t = time - (2*obj.stepTime+3*obj.interTime+obj.frequencyTime)*1e-3;
                    v = (obj.contrastMin+t*contrastDelta)*sin(2*pi*t*obj.contrastFrequency);
                else
                    v = 0;
                end
                c = obj.backgroundIntensity * v + obj.backgroundIntensity;
            end
            
        end
        
        % Same presentation each epoch in a run. Replay.
        function controllerDidStartHardware(obj)
            controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            if (obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < obj.numberOfAverages)
                obj.rig.getDevice('Stage').replay
            else
                obj.rig.getDevice('Stage').play(obj.createPresentation());
            end
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.interTime*3 + obj.stepTime*2 + obj.frequencyTime + obj.contrastTime;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end