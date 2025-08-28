classdef LedWeightModulation < edu.washington.riekelab.protocols.RiekeLabProtocol
    % Presents a set of rectangular pulse stimuli to a specified LED and records from a specified amplifier.
    
    properties
        preTime = 500                   % Pulse leading duration (ms)
        stimTime = 2500                 % Pulse duration (ms)
        tailTime = 500                  % Pulse trailing duration (ms)
        contrast = 1.0                  % Max contrast of pulses (0-1)
        temporalFrequency = 2.0         % Temporal frequency (Hz)
        ledMeans = [0.5,0.5,0.5]        % Led means in order of appearance.
        ledContrasts = [1,1,1]          % Led contrasts in order of appearance.
        temporalClass = 'sinewave'      % Temporal modulation (sine or squarewave)
        amp                             % Input amplifier
        onlineAnalysis = 'extracellular' % Online analysis type.
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties
        numberOfAverages = uint16(25)    % Number of epochs
        interpulseInterval = 1          % Duration between pulses (s)
    end
    
    properties (Hidden)
        ledType
        ampType
        ledMeansType = symphonyui.core.PropertyType('denserealdouble','matrix')
        ledContrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave','squarewave'})
        period = 500 % Default is 2Hz.
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            obj.ledType = obj.rig.getDeviceNames('LED');
%             [~, obj.ledType] = obj.createDeviceNamesProperty('LED');
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
                obj.ledType{1}, 0.5, 0.5));
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                if ~strcmp(obj.onlineAnalysis, 'none')
                    colors = winter(length(obj.stimulusNames));
                    obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                        obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                        'sweepColor',colors,...
                        'groupBy',{'stimulusName'});
                end
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
                obj.showFigure('edu.washington.riekelab.figures.DualMeanResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
            end
            
            % Loop through the LEDs and set the mean.
            for k = 1 : length(obj.ledType)
                device = obj.rig.getDevice(obj.ledType{k});
                device.background = symphonyui.core.Measurement(obj.ledMeans(k), device.background.displayUnits);
            end
            
            % Calculate the period from the temporal frequency.
            obj.period = 1/(obj.temporalFrequency * 1e-3);
        end
        
        function stim = createLedStimulus(obj, led, lightMean, lightAmplitude)
            
            if strcmp(obj.temporalClass,'sinewave')
                gen = symphonyui.builtin.stimuli.SineGenerator();
            else
                gen = symphonyui.builtin.stimuli.SquareGenerator();
            end
            gen.preTime = obj.preTime;
            gen.stimTime = obj.stimTime;
            gen.tailTime = obj.tailTime;
            gen.amplitude = lightAmplitude;
            gen.period = obj.period;      % Sine wave period (ms)
            gen.phase = 0;    % Sine wave phase offset (radians)
            gen.mean = lightMean;
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice(led).background.displayUnits;
            
            stim = gen.generate();
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);
            
            % Loop through the LEDs and set the weights.
            for k = 1 : length(obj.ledType)
                % Add the stimulus to the LED.
                    epoch.addStimulus(obj.rig.getDevice(obj.ledType{k}),...
                        obj.createLedStimulus(obj.ledType{idx},...
                        obj.ledMeans(k),...
                        obj.ledContrasts(k)));
            end
            
            epoch.addResponse(obj.rig.getDevice(obj.amp));
            
            if numel(obj.rig.getDeviceNames('Amp')) >= 2
                epoch.addResponse(obj.rig.getDevice(obj.amp2));
            end
        end
        
        function prepareInterval(obj, interval)
            prepareInterval@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, interval);
            
             % Loop through the LEDs and set the mean.
            for k = 1 : length(obj.ledType)
                device = obj.rig.getDevice(obj.ledType{k});
                interval.addDirectCurrentStimulus(device, device.background, obj.interpulseInterval, obj.sampleRate);
            end
            
%             device = obj.rig.getDevice(obj.led);
%             interval.addDirectCurrentStimulus(device, device.background, obj.interpulseInterval, obj.sampleRate);
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

