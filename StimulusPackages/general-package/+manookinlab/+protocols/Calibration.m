classdef Calibration < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Leading duration (ms)
        stimTime = 500                  % Stimulus duration (ms)
        tailTime = 0                    % Trailing duration (ms)
        width = 500                     % Width or diameter of stimulus in microns
        intensity = 1.0                 % Stimulus intensity (0-1)
        chromaticClass = 'white'        % Chromatic type
        stimulusClass = 'full intensity'         % Stimulus class
        shapeClass = 'circle'           % Shape class
        numberOfAverages = uint16(1)    % Number of epochs
    end
    
    properties (Hidden)
        ampType
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'white','black','red','green','blue'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'gamma ramp','full intensity'})
        shapeClassType = symphonyui.core.PropertyType('char', 'row', {'circle','square'})
        gammaRamp = 0:255
        rectColor
        width_pix
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
%             obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            obj.width_pix = obj.width/(10000.0/obj.rig.getDevice('Stage').um2pix(10000.0));
        end
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(0); % Set background intensity
            
            % Create the stimulus.
            if strcmp(obj.shapeClass, 'circle')
                rect = stage.builtin.stimuli.Ellipse();
                rect.radiusX = obj.width_pix/2.0;
                rect.radiusY = obj.width_pix/2.0;
            else
                rect = stage.builtin.stimuli.Rectangle();
                rect.size = [obj.width_pix, obj.width_pix]; %obj.canvasSize;
            end
            rect.color = obj.rectColor;
            rect.position = obj.canvasSize / 2;
            
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
            else
                obj.rectColor = obj.intensity * obj.rectColor;
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
