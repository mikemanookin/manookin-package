classdef PairedPulse < edu.washington.riekelab.protocols.RiekeLabProtocol
    properties
        amp               % Output amplifier
        preTime = 500     % Pulse leading duration (ms)
        pulse1Time = 2000 % Pulse1 duration (ms)
        interTime = 100   % Interpulse duration (ms)
        pulse2Time = 500  % Pulse2 duration (ms)
        tailTime = 1000   % Pulse trailing duration (ms)
        pulse1Amps   % Pulse1 amplitude (mV or pA)
        pulse2Amps   % Pulse2 amplitude (mV or pA)
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties
        amp2PulseAmplitude = 0          % Pulse amplitude for secondary amp (mV or pA depending on amp2 mode)
        numberOfAverages = uint16(10)    % Number of epochs
        interpulseInterval = 1          % Duration between pulses (s)
    end
    
    properties (Hidden)
        ampType
        pulse1Amplitude   % Pulse1 amplitude (mV or pA)
        pulse2Amplitude   % Pulse2 amplitude (mV or pA)
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function d = getPropertyDescriptor(obj, name)
            d = getPropertyDescriptor@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, name);
            
            if strncmp(name, 'amp2', 4) && numel(obj.rig.getDeviceNames('Amp')) < 2
                d.isHidden = true;
            end
        end
        
        function p = getPreview(obj, panel)
            p = symphonyui.builtin.previews.StimuliPreview(panel, @()obj.createAmpStimulus());
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
            end
            
            % Show the progress bar.
            obj.showFigure('edu.washington.riekelab.manookin.figures.ProgressFigure', obj.numberOfAverages);
        end
        
        function stim = createAmpStimulus(obj)
            gen = symphonyui.builtin.stimuli.PulseGenerator();
            
            gen.preTime = obj.preTime;
            gen.stimTime = obj.pulseDuration;
            gen.tailTime = obj.tailTime + (obj.stimTime-obj.pulseDuration);
            gen.amplitude = obj.pulseAmplitude;
            gen.mean = obj.rig.getDevice(obj.amp).background.quantity;
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice(obj.amp).background.displayUnits;
            
            stim = gen.generate();
        end
        
        function stim = createAmp2Stimulus(obj)
            gen = symphonyui.builtin.stimuli.PulseGenerator();
            
            gen.preTime = obj.preTime;
            gen.stimTime = obj.stimTime;
            gen.tailTime = obj.tailTime;
            gen.mean = obj.rig.getDevice(obj.amp2).background.quantity;
            gen.amplitude = obj.amp2PulseSignal - gen.mean;
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice(obj.amp2).background.displayUnits;
            
            stim = gen.generate();
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);
            
            obj.pulseDuration = obj.durations(mod(obj.numEpochsPrepared - 1, length(obj.durations)) + 1);
            stim = obj.createAmpStimulus();
            
            epoch.addStimulus(obj.rig.getDevice(obj.amp), stim);
            epoch.addResponse(obj.rig.getDevice(obj.amp));
            
            if numel(obj.rig.getDeviceNames('Amp')) >= 2
                epoch.addStimulus(obj.rig.getDevice(obj.amp2), obj.createAmp2Stimulus());
                epoch.addResponse(obj.rig.getDevice(obj.amp2));
            end
            epoch.addParameter('pulseDuration',obj.pulseDuration);
        end
        
        function prepareInterval(obj, interval)
            prepareInterval@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, interval);
            
            device = obj.rig.getDevice(obj.amp);
            interval.addDirectCurrentStimulus(device, device.background, obj.interpulseInterval, obj.sampleRate);
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

