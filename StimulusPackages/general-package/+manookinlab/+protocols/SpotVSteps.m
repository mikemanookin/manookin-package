classdef SpotVSteps < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Spot leading duration (ms)
        stimTime = 500                  % Spot duration (ms)
        tailTime = 1500                 % Spot trailing duration (ms)
        contrasts = [-1 -1 1 1]    % Contrasts (-1 to 1)
        innerRadii = [0 100 0 100]        % Inner radius in pixels.
        outerRadii = [100 200 100 200]      % Outer radius in pixels.
        chromaticClass = 'achromatic'   % Spot color
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        ECl = -55                       % Apparent chloride reversal (mV)
        voltageHolds = [-20 0 20 35 50 65 90 115 0] % Change in Vhold re to ECl (mV)
        centerOffset = [0,0]            % Center offset in pixels (x,y)        
        onlineAnalysis = 'analog'       % Online analysis type.
        numberOfAverages = uint16(45)    % Number of epochs (holds*(contrasts+1))
    end
    
    properties (Hidden)
        ampType
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','red','green','blue','yellow','S-iso','M-iso','L-iso','LM-iso'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        contrast
        intensity
        holdingPotential
        nextHold
        isDummyEpoch
        repsPerHold
        Vh
        allContrasts
        innerRadius
        outerRadius
        allInnerRadii
        allOuterRadii
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
            
            obj.repsPerHold = length(obj.contrasts) + 1;
            obj.Vh = ones(obj.repsPerHold,1)*obj.voltageHolds + obj.ECl; 
            obj.Vh = obj.Vh(:)';
            
            obj.allContrasts = [0, obj.contrasts(:)'];
            obj.allInnerRadii = [0, obj.innerRadii(:)'];
            obj.allOuterRadii = [0, obj.outerRadii(:)'];
            
            % Set the first holding potential.
            device = obj.rig.getDevice(obj.amp);
            device.background = symphonyui.core.Measurement(obj.Vh(1), device.background.displayUnits);
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Don't show the spot for dummy epochs.
            if ~obj.isDummyEpoch
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
                
                if obj.innerRadius > 0
                    mask = stage.builtin.stimuli.Ellipse();
                    mask.radiusX = obj.innerRadius;
                    mask.radiusY = obj.innerRadius;
                    mask.position = obj.canvasSize/2 + obj.centerOffset;
                    mask.color = obj.backgroundIntensity;
                    p.addStimulus(mask);
                end

                % Control when the spot is visible.
                spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(spotVisible);
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current contrast.
            if length(obj.contrasts) > 1
                obj.contrast = obj.allContrasts(mod(obj.numEpochsCompleted,length(obj.allContrasts))+1);
            else
                obj.contrast = obj.contrasts;
            end
            
            % Get the current inner radius.
            if length(obj.innerRadii) > 1
                obj.innerRadius = obj.allInnerRadii(mod(obj.numEpochsCompleted,length(obj.allInnerRadii))+1);
            else
                obj.innerRadius = obj.innerRadii;
            end
            
            % Get the current outer radius.
            if length(obj.outerRadii) > 1
                obj.outerRadius = obj.allOuterRadii(mod(obj.numEpochsCompleted,length(obj.allOuterRadii))+1);
            else
                obj.outerRadius = obj.outerRadii;
            end
            
            % Get the current holding potential.
            obj.holdingPotential = obj.Vh(mod(obj.numEpochsCompleted,length(obj.Vh))+1);
            if (obj.numEpochsCompleted+1) < obj.numberOfAverages
                obj.nextHold = obj.Vh(mod(obj.numEpochsCompleted+1,length(obj.Vh))+1);
            end
            
            % Determine whether this is a dummy epoch (i.e. no stimulus).
            obj.isDummyEpoch = (mod(obj.numEpochsCompleted,obj.repsPerHold) == 0);
            
            % Don't persist dummy epochs.
            if obj.isDummyEpoch
                epoch.shouldBePersisted = false;
            else
                epoch.shouldBePersisted = true;
            end
            
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

            % Save the epoch-specific parameters
            epoch.addParameter('contrast',obj.contrast);
            epoch.addParameter('holdingPotential',obj.holdingPotential);
            epoch.addParameter('innerRadius', obj.innerRadius);
            epoch.addParameter('outerRadius', obj.outerRadius);
            
            % Set the holding potential.
            device = obj.rig.getDevice(obj.amp);
            device.background = symphonyui.core.Measurement(obj.holdingPotential, device.background.displayUnits);
        end
        
        function completeEpoch(obj, epoch)
            completeEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Set the Amp background to the next hold.
            if (obj.numEpochsCompleted+1) < obj.numberOfAverages
                device = obj.rig.getDevice(obj.amp);
                device.background = symphonyui.core.Measurement(obj.nextHold, device.background.displayUnits);
            end
            
            
            % Get the frame times and frame rate and append to epoch.
%             [frameTimes, actualFrameRate] = obj.getFrameTimes(epoch);
%             epoch.addParameter('frameTimes', frameTimes);
%             epoch.addParameter('actualFrameRate', actualFrameRate);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end