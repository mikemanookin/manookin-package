classdef ConeRatioSearch < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 1500                 % Stimulus duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        radius = 200                    % Radius in pixels.
        temporalFrequency = 2.0         % Temporal frequency (Hz)
        greenContrasts = -0.54:0.02:-0.25  % Green LED contrasts (-0.54 -0.25 bracket the range)
        stimulusClass = 'full-field'    % Stimulus class
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular'         % Online analysis type.
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        numberOfAverages = uint16(45)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'spot','annulus', 'full-field'})
        ledContrasts
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
            p.setBackgroundColor(obj.backgroundIntensity*[1 1 0]);
            
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
                mask.radiusX = obj.radius;
                mask.radiusY = obj.radius;
                mask.position = obj.canvasSize/2 + obj.centerOffset;
                mask.color = obj.backgroundIntensity; 
                p.addStimulus(mask);
            end
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            % Control the spot color.
            colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                @(state)getSpotColor(obj, state.time - obj.preTime * 1e-3));
            p.addController(colorController);
            
            function c = getSpotColor(obj, time)
                if time > 0 && time <= obj.stimTime*1e-3
                    c = obj.backgroundIntensity * (obj.ledContrasts*sin(time*obj.temporalFrequency*2*pi)) + obj.backgroundIntensity;
                else
                    c = obj.backgroundIntensity*[1 1 0];
                end
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the led contrasts.
            obj.ledContrasts = [1, ...
                obj.greenContrasts(mod(obj.numEpochsCompleted,length(obj.greenContrasts))+1), ...
                0
                ];
            
            % Save the seed.
            epoch.addParameter('ledContrasts', obj.ledContrasts);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end