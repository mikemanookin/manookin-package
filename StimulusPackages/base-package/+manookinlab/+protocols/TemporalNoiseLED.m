classdef TemporalNoiseLED < edu.washington.riekelab.protocols.RiekeLabProtocol
    properties
        led                             % Output LED
        preTime = 250                   % Time before noise (ms)
        firstStimTime = 6000            % Noise duration with first stdev (ms)
        secondStimTime = 6000           % Noise duration with second stdev (ms)
        tailTime = 500                  % Time after noise (ms)
        lightMean = 2.0                 % Noise and LED background mean (V or norm. [0-1] depending on LED units)
        firstStdv = 0.3                 % First noise standard deviation, RMS contrast [0-1]
        secondStdv = 0.1                % First noise standard deviation, RMS contrast [0-1]
        randsPerRep = 10                % Number of random seeds per repeat
        frequencyCutoff = 60            % Noise frequency cutoff for smoothing (Hz)
        numberOfFilters = 4             % Number of filters in cascade for noise smoothing
        onlineAnalysis = 'extracellular'% Online analysis type.
        amp                             % Input amplifier
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties 
        numberOfAverages = uint16(25)    % Number of families
        interpulseInterval = 0.5        % Duration between noise stimuli (s)
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
            p = symphonyui.builtin.previews.StimuliPreview(panel, @()createPreviewStimuli(obj));
            function s = createPreviewStimuli(obj)
                s = obj.createLedStimulus(0);
            end
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                obj.showFigure('symphonyui.builtin.figures.MeanResponseFigure', obj.rig.getDevice(obj.amp));
                obj.showFigure('edu.washington.riekelab.figures.ProgressFigure', obj.numberOfAverages)
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
                obj.showFigure('edu.washington.riekelab.figures.DualMeanResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
            end
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.TemporalNoiseLEDFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType', obj.onlineAnalysis,...
                    'preTime', obj.preTime, 'stimTime', obj.firstStimTime+obj.secondStimTime);
            end
            
            device = obj.rig.getDevice(obj.led);
            device.background = symphonyui.core.Measurement(obj.lightMean, device.background.displayUnits);
        end
        
        function [stim] = createLedStimulus(obj, seed)
            
            % generate a stimulus with two generators
            % make the first noise stimulus
            gen1 = edu.washington.riekelab.stimuli.GaussianNoiseGeneratorV2();
            gen1.preTime = obj.preTime;
            gen1.stimTime = obj.firstStimTime;
            gen1.tailTime = obj.secondStimTime + obj.tailTime;
            gen1.stDev = obj.firstStdv * obj.lightMean;
            gen1.freqCutoff = obj.frequencyCutoff;
            gen1.numFilters = obj.numberOfFilters;
            gen1.mean = obj.lightMean;
            gen1.seed = seed;
            gen1.sampleRate = obj.sampleRate;
            gen1.units = obj.rig.getDevice(obj.led).background.displayUnits;
            if strcmp(gen1.units, symphonyui.core.Measurement.NORMALIZED)
                gen1.upperLimit = 1;
                gen1.lowerLimit = 0;
            else
                gen1.upperLimit = 10.239;
                gen1.lowerLimit = -10.24;
            end
            
            stim1 = gen1.generate();
            
            % make the second noise stimulus
            gen2 = edu.washington.riekelab.stimuli.GaussianNoiseGeneratorV2();
            gen2.preTime = obj.preTime + obj.firstStimTime;
            gen2.stimTime = obj.secondStimTime;
            gen2.tailTime = obj.tailTime;
            gen2.stDev = obj.secondStdv * obj.lightMean;
            gen2.freqCutoff = obj.frequencyCutoff;
            gen2.numFilters = obj.numberOfFilters;
            gen2.mean = 0;
            gen2.seed = seed;
            gen2.sampleRate = obj.sampleRate;
            gen2.units = obj.rig.getDevice(obj.led).background.displayUnits;
            if strcmp(gen2.units, symphonyui.core.Measurement.NORMALIZED)
                gen2.upperLimit = 1 - obj.lightMean;
                gen2.lowerLimit = 0;
            else
                gen2.upperLimit = 10.239 - obj.lightMean;
                gen2.lowerLimit = -10.24;
            end
            
            stim2 = gen2.generate();
            
            % sum them into one stimulus
            sumGen = symphonyui.builtin.stimuli.SumGenerator();
            sumGen.stimuli = {stim1, stim2};
            stim = sumGen.generate(); 
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);
            
            persistent seed;
            % Deal with the seed.
            if obj.randsPerRep <= 0 
                seed = 1;
%             elseif obj.randsPerRep > 0 && (mod(obj.numEpochsCompleted+1,obj.randsPerRep+1) == 0)
            elseif obj.randsPerRep > 0 && (mod(obj.numEpochsPrepared+1,obj.randsPerRep+1) == 0)
                seed = 1;
            else
                seed = RandStream.shuffleSeed;
            end

            stim = obj.createLedStimulus(seed);

            epoch.addParameter('seed', seed);
            epoch.addStimulus(obj.rig.getDevice(obj.led), stim);
            epoch.addResponse(obj.rig.getDevice(obj.amp));
            
            % Save the stimulus contrast.
            ct = (stim.getData() - obj.lightMean) / obj.lightMean;
            epoch.addParameter('contrast', ct);
            
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
    
end