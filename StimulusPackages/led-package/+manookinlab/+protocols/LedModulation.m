classdef LedModulation < edu.washington.riekelab.protocols.RiekeLabProtocol
    % Presents a set of rectangular pulse stimuli to a specified LED and records from a specified amplifier.
    
    properties
        preTime = 500                   % Pulse leading duration (ms)
        stimTime = 2500                 % Pulse duration (ms)
        tailTime = 500                  % Pulse trailing duration (ms)
        contrast = 1.0                  % Max contrast of pulses (0-1)
        temporalFrequency = 2.0         % Temporal frequency (Hz)
        ledMeans = [0.627,1.443,1.440]  % RGB Led means.
        stimulusClass = 'cone-typing'   % Chromatic axis to probe
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
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'cone-typing','blue-yellow', 'red-green', 'S-LM', 'L-M', 'all'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave','squarewave'})
        stimulusNames
        stimulusName
        ledNames = {'Red','Green','Blue'};
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
                'Green LED', 0.5, 0.5));
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            switch obj.stimulusClass
                case 'cone-typing'
                    obj.stimulusNames = {'BW','LM','S','L','M'};
                case 'blue-yellow'
                    obj.stimulusNames = {'BW','B-Y','Y-B'};
                case 'S-LM'
                    obj.stimulusNames = {'BW','B-Y','Y-B','S','LM'};
                case 'red-green'
                    obj.stimulusNames = {'BW','R-G','G-R'};
                case 'L-M'
                    obj.stimulusNames = {'BW','R-G','G-R','L','M'};
                case 'all'
                    obj.stimulusNames = {'BW','B-Y','Y-B','S','LM','R-G','G-R','L','M'};
            end
            
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
            
%             gen = symphonyui.builtin.stimuli.PulseGenerator();
%             gen.preTime = obj.preTime;
%             gen.stimTime = obj.stimTime;
%             gen.tailTime = obj.tailTime;
%             gen.amplitude = lightAmplitude;
%             gen.mean = lightMean;
%             gen.sampleRate = obj.sampleRate;
%             gen.units = obj.rig.getDevice(led).background.displayUnits;
            
            stim = gen.generate();
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);
            
            % Get the current stimulus name
            obj.stimulusName = obj.stimulusNames{mod(obj.numEpochsPrepared - 1,length(obj.stimulusNames))+1};
            epoch.addParameter('stimulusName',obj.stimulusName);
            
            % Get the LED amplitudes and cone contrast.
            [w, coneContrast] = obj.getLEDWeights();
            epoch.addParameter('coneContrast',obj.contrast*coneContrast);
            
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
            
%             device = obj.rig.getDevice(obj.led);
%             interval.addDirectCurrentStimulus(device, device.background, obj.interpulseInterval, obj.sampleRate);
        end
        
        % Get the LED weights.
        function [w, coneContrast] = getLEDWeights(obj)
            
            % Quantal catch matrix; this is a hack...
            % Rows are RGB
            % Columns are LMS
            Q = [
                0.23705,0.047286,0.00345;
                0.35184,0.49263,0.09975;
                0.03814,0.035375,0.16675;
                ];
            
            %'ON','OFF','B-Y','Y-B','S','LM'
            switch obj.stimulusName
                case 'BW'
                    deltaRGB = ones(1,3);
                case 'B-Y'
                    deltaRGB = [-1,-1,1];
                case 'Y-B'
                    deltaRGB = [1,1,-1];
                case 'R-G'
                    deltaRGB = [1,-1,0];
                case 'G-R'
                    deltaRGB = [-1,1,0];
                case 'S'
                    deltaRGB = obj.getDeltaRGB([0;0;1],Q);
                case 'L'
                    deltaRGB = obj.getDeltaRGB([1;0;0],Q);
                case 'M'
                    deltaRGB = obj.getDeltaRGB([0;1;0],Q);
                case 'LM'
                    deltaRGB = obj.getDeltaRGB([1;1;0],Q);
                otherwise
                    deltaRGB = ones(1,3);
            end
            deltaRGB = obj.contrast * deltaRGB;
            % Get the cone contrasts.
            coneContrast = obj.getConeContrasts(deltaRGB(:),Q);
            
            w = deltaRGB(:)'.*obj.ledMeans;
        end
        
        function deltaRGB = getDeltaRGB(obj,isoVec,Q)
            deltaRGB = 2*(Q.*(ones(3,1)*obj.ledMeans(:)')')' \ isoVec(:);
            deltaRGB = deltaRGB / max(abs(deltaRGB));
        end
        
        function cWeber = getConeContrasts(obj,deltaRGB,q)
            meanFlux = (obj.ledMeans(:)*ones(1,3)).*q(:,1:3);

            iDelta = sum((deltaRGB(:)*ones(1,3)).*meanFlux);
            % Calculate the max contrast of each cone type. (Weber contrast)
            cWeber = iDelta ./ sum(meanFlux,1);
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

