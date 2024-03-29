classdef MovingBarSpeedTuning < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Bar leading duration (ms)
        stimTime = 6000                 % Bar duration (ms)
        tailTime = 250                  % Bar trailing duration (ms)
        orientation = 0                 % Bar angle (deg)
        speeds = [0.5,1,2,4]*1000       % Bar speeds (mu/sec)
        contrasts = [-1, 1]             % Bar contrast
        barSize = [200, 3000]            % Bar size (x,y) in pixels
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        innerMaskRadius = 0             % Inner mask radius in pixels.
        outerMaskRadius = 0           % Outer mask radius in pixels.
        onlineAnalysis = 'none'         % Online analysis type.
        numberOfAverages = uint16(96)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        speedsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        contrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        sequence
        orientationRads
        speed
        speedPix
        contrast
        intensity
        barSizePix
        startPix
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            % Check the outer mask radius.
%             if obj.outerMaskRadius > min(obj.canvasSize/2)
%                 obj.outerMaskRadius = min(obj.canvasSize/2);
%             end
            
            obj.barSizePix = obj.rig.getDevice('Stage').um2pix(obj.barSize);
            if obj.outerMaskRadius == 0
                obj.startPix = -obj.canvasSize(1)/2;
            end
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.barSizePix;
            rect.position = obj.canvasSize/2;
            rect.orientation = obj.orientation;
            rect.color = obj.intensity;
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect);
            
            barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(barVisible);
            
            % Bar position controller
            barPosition = stage.builtin.controllers.PropertyController(rect, 'position', ...
                @(state)motionTable(obj, state.time - obj.preTime*1e-3));
            p.addController(barPosition);
            
            function p = motionTable(obj, time)
                % Calculate the increment with time.  
                inc = time * obj.speedPix + obj.startPix - obj.barSizePix(1)/2;
                
                p = [cos(obj.orientationRads) sin(obj.orientationRads)] .* (inc*ones(1,2)) + obj.canvasSize/2;
            end
            
            % Create the inner mask.
            if (obj.innerMaskRadius > 0)
                p.addStimulus(obj.makeInnerMask());
            end
            
            % Create the outer mask.
            if (obj.outerMaskRadius > 0)
                p.addStimulus(obj.makeOuterMask());
            end
        end
        
        function mask = makeOuterMask(obj)
            mask = stage.builtin.stimuli.Rectangle();
            mask.color = obj.backgroundIntensity;
            mask.position = obj.canvasSize/2;
            mask.orientation = 0;
            mask.size = 2 * max(obj.canvasSize) * ones(1,2);
            sc = obj.outerMaskRadius*2 / (2*max(obj.canvasSize));
            m = stage.core.Mask.createCircularAperture(sc);
            mask.setMask(m);
        end
        
        function mask = makeInnerMask(obj)
            mask = stage.builtin.stimuli.Ellipse();
            mask.radiusX = obj.innerMaskRadius;
            mask.radiusY = obj.innerMaskRadius;
            mask.color = obj.backgroundIntensity;
            mask.position = obj.canvasSize/2;
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.contrast = obj.contrasts(mod(obj.numEpochsCompleted, length(obj.contrasts))+1);
            if obj.backgroundIntensity > 0
                obj.intensity = obj.contrast*obj.backgroundIntensity + obj.backgroundIntensity;
            else
                obj.intensity = obj.contrast;
            end
            
            % Get the current bar speed.
            obj.speed = obj.speeds(mod(floor(obj.numEpochsCompleted/length(obj.contrasts)), length(obj.speeds))+1);
            obj.speedPix = obj.rig.getDevice('Stage').um2pix(obj.speed);
            obj.orientationRads = obj.orientation / 180 * pi;
        
            epoch.addParameter('speed', obj.speed);
            epoch.addParameter('speedDegPerSec', obj.speed/250);
            epoch.addParameter('contrast', obj.contrast);
        end
        
        % Same presentation each epoch in a run. Replay.
        function controllerDidStartHardware(obj)
            controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            if (obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < obj.numberOfAverages) && length(obj.speeds)==1
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