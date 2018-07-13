classdef ChromaticSpot < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Spot leading duration (ms)
        stimTime = 500                  % Spot duration (ms)
        tailTime = 500                  % Spot trailing duration (ms)
        contrast = 1.0                  % Contrast (-1 to 1)
        innerRadius = 0                 % Inner radius in pixels.
        outerRadius = 1000              % Outer radius in pixels.
        chromaticClass = 'achromatic'   % Spot color
        backgroundIntensity = 0.0       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)        
        onlineAnalysis = 'none'         % Online analysis type.
        numberOfAverages = uint16(1)    % Number of epochs
    end
    
    properties (Hidden)
        ampType
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','red','green','blue','yellow','S-iso','M-iso','L-iso','LM-iso'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        intensity
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('symphonyui.builtin.figures.MeanResponseFigure', obj.rig.getDevice(obj.amp));
            
            % Get the canvas size.
            obj.canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            
            % Check the chromatic type to set the intensity.
            if strcmp(obj.stageClass, 'Video')
                % Set the LED weights.
                obj.setColorWeights();
                if obj.backgroundIntensity > 0
                    obj.intensity = obj.backgroundIntensity * (obj.contrast * obj.colorWeights) + obj.backgroundIntensity;
                else
                    if isempty(strfind(obj.chromaticClass, 'iso'))
                        obj.intensity = obj.colorWeights * obj.contrast;
                    else
                        obj.intensity = obj.contrast * (0.5 * obj.colorWeights + 0.5);
                    end
                end
            else
                if obj.backgroundIntensity > 0
                    obj.intensity = obj.backgroundIntensity * obj.contrast + obj.backgroundIntensity;
                else
                    obj.intensity = obj.contrast;
                end
            end
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            spot = stage.builtin.stimuli.Ellipse();
            spot.radiusX = obj.outerRadius;
            spot.radiusY = obj.outerRadius;
            spot.position = obj.canvasSize/2 + obj.centerOffset;
            if strcmp(obj.stageClass, 'Video')
                spot.color = obj.intensity;
            else
                spot.color = obj.intensity(1);
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            % Add inner radius mask.
            if obj.innerRadius > 0
                mask = stage.builtin.stimuli.Ellipse();
                mask.radiusX = obj.innerRadius;
                mask.radiusY = obj.innerRadius;
                mask.position = obj.canvasSize/2 + obj.centerOffset;
                if strcmp(obj.stageClass, 'Video')
                    mask.color = obj.backgroundIntensity;
                else
                    mask.color = obj.backgroundIntensity;
                end

                % Add the stimulus to the presentation.
                p.addStimulus(mask);
            end
            
            if strcmp(obj.stageClass, 'LcrRGB')
                % Control the spot color.
                colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                    @(state)getSpotColor(obj, state));
                p.addController(colorController);
            end
            
            function c = getSpotColor(obj, state)
                if state.pattern == 0
                    c = obj.intensity(1);
                elseif state.pattern == 1
                    c = obj.intensity(2);
                else
                    c = obj.intensity(3);
                end
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
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end