classdef Calibration < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % leading duration (ms)
        stimTime = 500                 % duration (ms)
        tailTime = 0 
        chromaticClass = 'white'        % Chromatic type
        stimulusClass = 'gamma ramp'         % Stimulus class
        numberOfAverages = uint16(256)    % Number of epochs
    end
    
    properties (Hidden)
        ampType
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'white','black','red','green','blue'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'gamma ramp','full intensity'})
        gammaRamp = 0:255
        rectColor
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
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.rectColor); % Set background intensity
            
            % Create the stimulus.
            rect = stage.builtin.stimuli.Rectangle();
            rect.color = obj.rectColor;
            rect.position = obj.canvasSize / 2;
            rect.size = obj.canvasSize;
            
            % Add the rectangle.
            p.addStimulus(rect);
            
            % Make the grating visible only during the stimulus time.
            grateVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(grateVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            switch obj.chromaticClass
                case 'white'
                    obj.rectColor = [1 1 1];
                case 'black'
                    obj.rectColor = [0 0 0];
                case 'red'
                    obj.rectColor = [1 0 0];
                case 'green'
                    obj.rectColor = [0 1 0];
                case 'blue'
                    obj.rectColor = [0 0 1];
                otherwise
                    obj.rectColor = [1 1 1];
            end
            
            if strcmp(obj.stimulusClass, 'gamma ramp')
                % Get the current gamma value.
                g = obj.gammaRamp( obj.numEpochsCompleted+1 );
                % Set the rect color.
                obj.rectColor = g/255*obj.rectColor;
                
                epoch.addParameter('gammaValue', g);
            end
            
            epoch.addParameter('rectColor', obj.rectColor);

        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end