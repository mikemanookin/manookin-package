classdef ManualCentering < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Spot leading duration (ms)
        stimTime = 10000                % Spot duration (ms)
        tailTime = 250                  % Spot trailing duration (ms)
        intensity = 1.0
        temporalFrequency = 1.0         % Modulation frequency (Hz)
        size = [100 100]                   
        backgroundIntensity = 0.0       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        numberOfAverages = uint16(1)   % Number of epochs
    end    
    
    properties (Hidden, Transient)
        analysisFigure
    end
    
    properties (Hidden)
        ampType
        displayFrame
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            obj.displayFrame = floor((obj.preTime+obj.stimTime)*1e-3 * obj.frameRate);
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.size;
            rect.position = obj.canvasSize/2 + obj.centerOffset;
            rect.color = obj.intensity;
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect);       
            
            % Control when the spot is visible.
            rectVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(rectVisible);
            
            % Control the spot intensity.
            colorController = stage.builtin.controllers.PropertyController(rect, 'color', ...
                @(state)getRectColorVideoSqwv(obj, state.time - obj.preTime * 1e-3));
            p.addController(colorController);
            
            function c = getRectColorVideoSqwv(obj, time)
                c = obj.intensity * sign(sin(obj.temporalFrequency*time*2*pi)) * 0.5 + 0.5;
            end
            
            % window = state.canvas.window; currentPosition =
            % spot.position;
            positionController = stage.builtin.controllers.PropertyController(rect, 'position', ...
                @(state)moveSpot(obj, state.canvas.window, rect.position, state.frame));
            p.addController(positionController);
            
            function p = moveSpot(obj, window, currentPosition, frame)
                p = currentPosition;
                if window.getKeyState(GLFW.GLFW_KEY_UP)
                    p(2) = p(2) + 1;
                end
                if window.getKeyState(GLFW.GLFW_KEY_DOWN)
                    p(2) = p(2) - 1;
                end
                if window.getKeyState(GLFW.GLFW_KEY_LEFT)
                    p(1) = p(1) - 1;
                end
                if window.getKeyState(GLFW.GLFW_KEY_RIGHT)
                    p(1) = p(1) + 1;
                end
                
                if frame == obj.displayFrame
                    disp(['position: ', num2str(p - obj.canvasSize/2)]);
                end
            end
            
            % Change the rect size.
            sizeController = stage.builtin.controllers.PropertyController(rect, 'size', ...
                @(state)rectSize(obj, state.canvas.window, rect.size, state.frame));
            p.addController(sizeController);
            
            function s = rectSize(obj, window, currentSize, frame)
                s = currentSize;
                if window.getKeyState(GLFW.GLFW_KEY_W)
                    s(2) = s(2) + 3;
                end
                if window.getKeyState(GLFW.GLFW_KEY_S)
                    s(2) = s(2) - 3;
                end
                if window.getKeyState(GLFW.GLFW_KEY_A)
                    s(1) = s(1) - 3;
                end
                if window.getKeyState(GLFW.GLFW_KEY_D)
                    s(1) = s(1) + 3;
                end
                
                if frame == obj.displayFrame
                    disp(['size: ', num2str(s)]);
                end
            end

        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);

%             device = obj.rig.getDevice(obj.amp);
%             duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
%             epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
%             epoch.addResponse(device);
        end
        
        function completeEpoch(obj, epoch)
            completeEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end