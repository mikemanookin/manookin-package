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
        onlineAnalysis = 'extracellular' % Online analysis type.
        numberOfAverages = uint16(1)    % Number of epochs
    end
    
    properties (Hidden)
        ampType
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','red','green','blue','yellow','S-iso','M-iso','L-iso','LM-iso'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        intensity
        bgMean
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',[30 144 255]/255,...
                    'groupBy',{'frameRate'});
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
                obj.showFigure('edu.washington.riekelab.figures.DualMeanResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
            end
            
            % Check the chromatic type to set the intensity.
            if strcmp(obj.stageClass, 'Video')
                % Set the LED weights.
                if contains(obj.chromaticClass,'iso')
                    [obj.bgMean, ~, obj.colorWeights] = manookinlab.util.getMaxContrast(obj.quantalCatch, obj.chromaticClass);
                    obj.bgMean = obj.bgMean(:)';
                    obj.colorWeights = obj.colorWeights(:)';
                else
                    obj.setColorWeights();
                    obj.bgMean = 0.5*ones(1,3);
                end
                if obj.backgroundIntensity > 0
                    obj.intensity = obj.bgMean .* (obj.contrast * obj.colorWeights) + obj.bgMean;
                else
                    if isempty(strfind(obj.chromaticClass, 'iso'))
                        obj.intensity = obj.colorWeights * obj.contrast;
                    else
                        obj.intensity = obj.contrast * (0.5 .* obj.colorWeights + 0.5);
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
            if ~strcmp(obj.chromaticClass,'achromatic') && strcmp(obj.stageClass,'Video')
                p.setBackgroundColor(obj.bgMean);
            else
                p.setBackgroundColor(obj.backgroundIntensity);
            end
            
            spot = stage.builtin.stimuli.Ellipse();
            spot.radiusX = obj.outerRadius;
            spot.radiusY = obj.outerRadius;
            spot.position = obj.canvasSize/2;
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
                mask.position = obj.canvasSize/2;
                if ~strcmp(obj.chromaticClass,'achromatic') && strcmp(obj.stageClass,'Video')
                    mask.color = obj.bgMean;
                else
                    mask.color = obj.backgroundIntensity;
                end

                % Add the stimulus to the presentation.
                p.addStimulus(mask);
            end
            
        end
        
        function a = get.amp2(obj)
            amps = obj.rig.getDeviceNames('Amp');
            if numel(amps) < 2
                a = '(None)';
            else
                i = find(~ismember(amps, obj.amp), 1);
                a = amps{i};
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