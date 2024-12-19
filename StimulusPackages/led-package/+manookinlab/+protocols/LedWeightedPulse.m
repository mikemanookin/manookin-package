classdef LedWeightedPulse < edu.washington.riekelab.protocols.RiekeLabProtocol
    % Presents a set of rectangular pulse stimuli to a specified LED and records from a specified amplifier.
    
    properties
%         led                             % Output LED
        preTime = 500                   % Pulse leading duration (ms)
        stimTime = 500                  % Pulse duration (ms)
        tailTime = 1500                 % Pulse trailing duration (ms)
        ledMeans = [0.5,0.5,0.5]        % RGB LED background mean (V or norm. [0-1] depending on LED units)
        redContrasts = [0.19,0.19,1]
        greenContrasts = [-0.69,-0.6,1]
        blueContrasts = [1.0,1.0,0.0]
        amp                             % Input amplifier
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties
        numberOfAverages = uint16(12)   % Number of epochs
        interpulseInterval = 0.5        % Duration between pulses (s)
    end
    
    properties (Hidden)
        ledType
        ampType
        ledMeansType = symphonyui.core.PropertyType('denserealdouble','matrix')
        redContrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        greenContrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        blueContrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        ledNames = {'Red','Green','Blue'};
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
%             [obj.led, obj.ledType] = obj.createDeviceNamesProperty('LED');
            obj.ledType = obj.rig.getDeviceNames('LED');
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function d = getPropertyDescriptor(obj, name)
            d = getPropertyDescriptor@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, name);
            
            if strncmp(name, 'amp2', 4) && numel(obj.rig.getDeviceNames('Amp')) < 2
                d.isHidden = true;
            end
        end
        
        function p = getPreview(obj, panel)
            p = symphonyui.builtin.previews.StimuliPreview(panel, @()obj.createLedStimulus(...
                'Green LED', 0.5, 0.5));
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                obj.showFigure('symphonyui.builtin.figures.MeanResponseFigure', obj.rig.getDevice(obj.amp));
                obj.showFigure('symphonyui.builtin.figures.ResponseStatisticsFigure', obj.rig.getDevice(obj.amp), {@mean, @var}, ...
                    'baselineRegion', [0 obj.preTime], ...
                    'measurementRegion', [obj.preTime obj.preTime+obj.stimTime]);
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
                obj.showFigure('edu.washington.riekelab.figures.DualMeanResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
                obj.showFigure('edu.washington.riekelab.figures.DualResponseStatisticsFigure', obj.rig.getDevice(obj.amp), {@mean, @var}, obj.rig.getDevice(obj.amp2), {@mean, @var}, ...
                    'baselineRegion1', [0 obj.preTime], ...
                    'measurementRegion1', [obj.preTime obj.preTime+obj.stimTime], ...
                    'baselineRegion2', [0 obj.preTime], ...
                    'measurementRegion2', [obj.preTime obj.preTime+obj.stimTime]);
            end
%             
            % Loop through the LEDs and set the mean.
            for k = 1 : length(obj.ledNames)
                idx = [];
                for m = 1 : length(obj.ledType)
                    if ~isempty(strfind(obj.ledType{m},obj.ledNames{k}))
                        idx = m;
                    end
                end
                
                if ~isempty(idx)
                    device = obj.rig.getDevice(obj.ledType{idx});
                    device.background = symphonyui.core.Measurement(obj.ledMeans(k), device.background.displayUnits);
                end
            end
        end
        
        function stim = createLedStimulus(obj, led, lightMean, lightAmplitude)
            gen = symphonyui.builtin.stimuli.PulseGenerator();
            
            gen.preTime = obj.preTime;
            gen.stimTime = obj.stimTime;
            gen.tailTime = obj.tailTime;
            gen.amplitude = lightAmplitude;
            gen.mean = lightMean;
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice(led).background.displayUnits;
            
            stim = gen.generate();
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);
            
            % Get the LED contrasts.
            redContrast = obj.redContrasts(mod(obj.numEpochsPrepared - 1,length(obj.redContrasts))+1);
            greenContrast = obj.greenContrasts(mod(obj.numEpochsPrepared - 1,length(obj.greenContrasts))+1);
            blueContrast = obj.blueContrasts(mod(obj.numEpochsPrepared - 1,length(obj.blueContrasts))+1);
            epoch.addParameter('redContrast',redContrast);
            epoch.addParameter('greenContrast',greenContrast);
            epoch.addParameter('blueContrast',blueContrast);
            w = [redContrast,greenContrast,blueContrast] .* obj.ledMeans;
            
            % Loop through the LEDs and set the weights.
            for k = 1 : length(obj.ledNames)
                idx = [];
                for m = 1 : length(obj.ledType)
                    if ~isempty(strfind(obj.ledType{m},obj.ledNames{k}))
                        idx = m;
                    end
                end
                
                if ~isempty(idx)
                    % Add the stimulus to the LED.
                    epoch.addStimulus(obj.rig.getDevice(obj.ledType{idx}),...
                        obj.createLedStimulus(obj.ledType{idx},...
                        obj.ledMeans(k),...
                        w(k)));
                end
            end
            
            epoch.addResponse(obj.rig.getDevice(obj.amp));
            
            if numel(obj.rig.getDeviceNames('Amp')) >= 2
                epoch.addResponse(obj.rig.getDevice(obj.amp2));
            end
        end
        
        function prepareInterval(obj, interval)
            prepareInterval@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, interval);
            
             % Loop through the LEDs and set the mean.
            for k = 1 : length(obj.ledNames)
                idx = [];
                for m = 1 : length(obj.ledType)
                    if ~isempty(strfind(obj.ledType{m},obj.ledNames{k}))
                        idx = m;
                    end
                end
                
                if ~isempty(idx)
                    device = obj.rig.getDevice(obj.ledType{idx});
                    interval.addDirectCurrentStimulus(device, device.background, obj.interpulseInterval, obj.sampleRate);
                end
            end
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
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
        
    end
    
end

