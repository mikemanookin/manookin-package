classdef MovingBarInOut < edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 0                     % Bar leading duration (ms)
        stimTime = 2000                 % Bar duration (ms)
        tailTime = 0                    % Bar trailing duration (ms)
        waitTime = 1000                 % Bar wait time before motion (ms)
        orientation = 0                 % Bar angle (deg)
        speed = 500                     % Bar speed (pix/sec)
        contrasts = [0.25 0.25 0.5 0.75 1] % Bar contrasts [-1, 1]
        barSize = [50, 50]              % Bar size (x,y) in pixels
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        maxRadius = 100                 % Max radius for motion in pixels
        onlineAnalysis = 'extracellular'         % Online analysis type.
        numberOfAverages = uint16(36)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        sequence
        directions = {'outward','inward'}
        direction
        orientationRads
        contrast
        intensity
        startPosition
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj);
            
            colors = pmkmp(length(obj.directions),'CubicYF');
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.manookin.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'direction'});
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.barSize;
            if strcmp(obj.direction,'outward')
                rect.position = obj.canvasSize/2 + obj.centerOffset;
            else
                rect.position = obj.canvasSize/2 + obj.centerOffset + [cos(obj.orientationRads) sin(obj.orientationRads)]*obj.maxRadius;
            end
            rect.orientation = obj.orientation;
            rect.color = obj.intensity;
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect);
            
            barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time <= (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(barVisible);
            
            % Bar position controller
            if strcmp(obj.direction,'outward')
                barPosition = stage.builtin.controllers.PropertyController(rect, 'position', ...
                    @(state)motionTableOut(obj, state.time - (obj.preTime+obj.waitTime)*1e-3));
            else
                barPosition = stage.builtin.controllers.PropertyController(rect, 'position', ...
                    @(state)motionTableIn(obj, state.time - (obj.preTime+obj.waitTime)*1e-3));
            end
            p.addController(barPosition);
            
            function p = motionTableOut(obj, time)
                % Calculate the increment with time.  
                if time <= 0
                    inc = 0;
                else
                    inc = min(time * obj.speed - obj.startPosition, obj.maxRadius);
                end
                
                p = [cos(obj.orientationRads) sin(obj.orientationRads)] .* (inc*ones(1,2)) + obj.canvasSize/2 + obj.centerOffset;
            end
            
            function p = motionTableIn(obj, time)
                % Calculate the increment with time.  
                if time <= 0
                    inc = obj.maxRadius;
                else
                    inc = max(obj.startPosition - time * obj.speed, 0);
                end
                
                p = [cos(obj.orientationRads) sin(obj.orientationRads)] .* (inc*ones(1,2)) + obj.canvasSize/2 + obj.centerOffset;
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current bar orientation.
            obj.orientationRads = obj.orientation / 180 * pi;
            
            obj.direction = obj.directions{mod(obj.numEpochsCompleted,2)+1};
            obj.contrast = obj.contrasts(mod(floor(obj.numEpochsCompleted/2),length(obj.contrasts))+1);
            if strcmp(obj.direction,'outward')
                obj.startPosition = 0;
            else
                obj.startPosition = obj.maxRadius;
            end
            if (obj.backgroundIntensity <= 0)
                obj.intensity = abs(obj.contrast);
            else
                obj.intensity = obj.contrast*obj.backgroundIntensity+obj.backgroundIntensity;
            end
            
            epoch.addParameter('direction', obj.direction);
            epoch.addParameter('contrast', obj.contrast);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end