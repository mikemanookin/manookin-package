classdef ChirpStimulusLED < edu.washington.riekelab.protocols.RiekeLabProtocol
    % Presents a chirp stimulus ala Euler to a specified LED and records from a specified amplifier.
    
    properties
        led                             % Output LED
        amp                             % Input amplifier
        stepTime = 500                  % Step duration (ms)
        frequencyTime = 15000           % Frequency sweep duration (ms)
        contrastTime = 8000             % Contrast sweep duration (ms)
        interTime = 500                % Duration between stimuli (ms)
        stepContrast = 1.0              % Step contrast (0 - 1)
        frequencyContrast = 1.0         % Contrast during frequency sweep (0-1)
        frequencyMin = 0.0              % Minimum temporal frequency (Hz)
        frequencyMax = 10.0             % Maximum temporal frequency (Hz)
        contrastMin = 0.02              % Minimum contrast (0-1)
        contrastMax = 1.0               % Maximum contrast (0-1)
        contrastFrequency = 2.0         % Temporal frequency of contrast sweep (Hz)
        backgroundIntensity = 1.0       % Background light intensity (0-5)
        psth = false;                   % Toggle psth in mean response figure
        onlineAnalysis = 'extracellular'         % Online analysis type.
    end
 
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties
        numberOfAverages = uint16(3)    % Number of epochs
        interpulseInterval = 0          % Duration between pulses (s)
    end
    
    properties (Hidden)
        ledType
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            [obj.led, obj.ledType] = obj.createDeviceNamesProperty('LED');
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function d = getPropertyDescriptor(obj, name)
            d = getPropertyDescriptor@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, name);
            
            if strncmp(name, 'amp2', 4) && numel(obj.rig.getDeviceNames('Amp')) < 2
                d.isHidden = true;
            end
        end
        
        function p = getPreview(obj, panel)
            p = symphonyui.builtin.previews.StimuliPreview(panel, @()obj.createChirpStimulus());
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                obj.showFigure('edu.washington.riekelab.figures.MeanResponseFigure', obj.rig.getDevice(obj.amp),'psth',obj.psth);
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
                obj.showFigure('edu.washington.riekelab.figures.DualMeanResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
            end
            
            device = obj.rig.getDevice(obj.led);
            device.background = symphonyui.core.Measurement(obj.backgroundIntensity, device.background.displayUnits);
        end
        
        function stim = createChirpStimulus(obj)
            gen = manookinlab.stimuli.ChirpStimulusGenerator();
                        
            gen.stepTime = obj.stepTime;
            gen.frequencyTime = obj.frequencyTime;
            gen.contrastTime = obj.contrastTime;
            gen.interTime = obj.interTime;
            gen.frequencyContrast = obj.frequencyContrast;
            gen.stepContrast = obj.stepContrast;
            gen.frequencyMin = obj.frequencyMin;
            gen.frequencyMax = obj.frequencyMax;
            gen.contrastMin = obj.contrastMin;
            gen.contrastMax = obj.contrastMax;
            gen.contrastFrequency = obj.contrastFrequency;
            gen.backgroundIntensity = obj.backgroundIntensity;
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice(obj.led).background.displayUnits;
            
            stim = gen.generate();
        
        end
               
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);
            
            epoch.addStimulus(obj.rig.getDevice(obj.led), obj.createChirpStimulus());
            epoch.addResponse(obj.rig.getDevice(obj.amp));
            
            if numel(obj.rig.getDeviceNames('Amp')) >= 2
                epoch.addResponse(obj.rig.getDevice(obj.amp2));
            end
        end
        
        function prepareInterval(obj, interval)
            prepareInterval@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, interval);
            
            device = obj.rig.getDevice(obj.led);
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
    
    
    
    
    
    
    
    
    
    
%     properties (Dependent, SetAccess = private)
%         amp2                            % Secondary amplifier
%     end
%     
%     properties
%          interpulseInterval = 0          % Duration between pulses (s)
%     end
%     
%     properties (Hidden)
%         ledType
%         ampType
%     end
%     
%     methods
%         
%         function didSetRig(obj)
%             didSetRig@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
%             
%             [obj.led, obj.ledType] = obj.createDeviceNamesProperty('LED');
%             [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
%         end
%         
%         function d = getPropertyDescriptor(obj, name)
%             d = getPropertyDescriptor@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, name);
%             
%             if strncmp(name, 'amp2', 4) && numel(obj.rig.getDeviceNames('Amp')) < 2
%                 d.isHidden = true;
%             end
%         end
%         
%         function p = getPreview(obj, panel)
%             p = symphonyui.builtin.previews.StimuliPreview(panel, @()obj.createChirpStimulus());
%         end
%         
%         function prepareRun(obj)
%             prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
%             
%             if numel(obj.rig.getDeviceNames('Amp')) < 2
%                 obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
%                 obj.showFigure('edu.washington.riekelab.figures.MeanResponseFigure', obj.rig.getDevice(obj.amp),'psth',obj.psth);
%             else
%                 obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
%                 obj.showFigure('edu.washington.riekelab.figures.DualMeanResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
%              end
%             
%             device = obj.rig.getDevice(obj.led);
%             device.background = symphonyui.core.Measurement(obj.backgroundIntensity, device.background.displayUnits);
%         end
%         
%         function stim = createChirpStimulus(obj)
% %             frequencyDelta = (obj.frequencyMax - obj.frequencyMin)/(obj.frequencyTime*1e-3);
% %             contrastDelta = (obj.contrastMax - obj.contrastMin)/(obj.contrastTime*1e-3);
%             
% %             totTime = obj.interTime*5 + obj.stepTime*2 + obj.frequencyTime + obj.contrastTime;
% %             totPts = totTime * obj.sampleRate * 1e-3;
% totPts = 10000;
% %             interPts = obj.interTime * obj.sampleRate * 1e-3;
% %             stepPts = obj.stepTime * obj.sampleRate * 1e-3;
% %             freqPts = obj.frequencyTime * obj.sampleRate * 1e-3;
% %             contrastPts = obj.contrastTime * obj.sampleRate * 1e-3;
%            
%             stim(1:totPts) = obj.backgroundIntensity;
% %             stim(interPts+1:interPts+stepPts) = stim(interPts+1:interPts+stepPts) + obj.stepContrast * obj.backgroundIntensity;
% %             stim(interPts*2+stepPts+1:interPts*2+stepPts*2) = stim(interPts*2+stepPts+1:interPts*2+stepPts*2) - obj.stepContrast * obj.backgroundIntensity;
% 
% %             for t = 1:freqPts
% %                 stim(t + interPts*3+stepPts*2) = obj.frequencyContrast*sin(2*pi*(obj.frequencyMin*t+frequencyDelta*t.^2)) + obj.backgroundIntensity;
% %             end
% %             
% %             for t = 1:contrastPts
% %                 stim(t + interPts*4+stepPts*2+freqPts) = (obj.contrastMin+t*contrastDelta)*sin(2*pi*t*obj.contrastFrequency) + obj.backgroundIntensity;
% %             end               
%         
%         end
%         
%         function prepareEpoch(obj, epoch)
%             prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);
%             
%             epoch.addStimulus(obj.rig.getDevice(obj.led), obj.createChirpStimulus());
%             epoch.addResponse(obj.rig.getDevice(obj.amp));
%             
%             if numel(obj.rig.getDeviceNames('Amp')) >= 2
%                 epoch.addResponse(obj.rig.getDevice(obj.amp2));
%             end
%         end
%         
%         function prepareInterval(obj, interval)
%             prepareInterval@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, interval);
%             
%             device = obj.rig.getDevice(obj.led);
%             interval.addDirectCurrentStimulus(device, device.background, obj.interpulseInterval, obj.sampleRate);
%         end
%         
%         function tf = shouldContinuePreparingEpochs(obj)
%             tf = obj.numEpochsPrepared < obj.numberOfAverages;
%         end
%         
%         function tf = shouldContinueRun(obj)
%             tf = obj.numEpochsCompleted < obj.numberOfAverages;
%         end
%         
%         function a = get.amp2(obj)
%             amps = obj.rig.getDeviceNames('Amp');
%             if numel(amps) < 2
%                 a = '(None)';
%             else
%                 i = find(~ismember(amps, obj.amp), 1);
%                 a = amps{i};
%             end
%         end
%         
%     end
    
end
