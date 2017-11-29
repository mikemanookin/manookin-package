classdef ResistanceAndCapacitance < edu.washington.riekelab.protocols.RiekeLabProtocol
    properties
        amp                             % Output amplifier
        preTime = 15                    % Stimulus leading duration (ms)
        stimTime = 30                   % Stimulus duration (ms)
        tailTime = 15                   % Stimulus trailing duration (ms)
        pulseAmplitude = 5              % Stimulus amplitude (mV or pA)
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties
        amp2PulseAmplitude = 0          % Pulse amplitude for secondary amp (mV or pA depending on amp2 mode)
        numberOfAverages = uint16(20)    % Number of epochs
        interpulseInterval = 0          % Duration between pulses (s)
    end
    
    properties (Hidden)
        ampType
        cumulativeData
        analysisFigure
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
            
            if isempty(obj.analysisFigure) || ~isvalid(obj.analysisFigure)
                obj.analysisFigure = obj.showFigure('symphonyui.builtin.figures.CustomFigure', @obj.updateFigure);
                f = obj.analysisFigure.getFigureHandle();
                set(f, 'Name', 'Resistance and Capacitance');
                obj.analysisFigure.userData.axesHandle = axes('Parent', f);
            end
            
            % Show the progress bar.
            obj.showFigure('edu.washington.riekelab.manookin.figures.ProgressFigure', obj.numberOfAverages);
            
            obj.cumulativeData = [];
        end
        
        function updateFigure(obj, ~, epoch)
            % Get the axes handle and clear it.
            axesHandle = obj.analysisFigure.userData.axesHandle;
            cla(axesHandle);
            
            r = epoch.getResponse(obj.rig.getDevice(obj.amp));
            response = r.getData();
            sampleRate = r.sampleRate.quantityInBaseUnits;
            
            if isempty(obj.cumulativeData)
                obj.cumulativeData = response;
            else
                obj.cumulativeData = obj.cumulativeData + response;
            end
            
            if obj.numEpochsCompleted < obj.numberOfAverages
                text(axesHandle, 0.5, 0.5, 'Accumulating data...', 'FontSize', 20, 'HorizontalAlignment', 'center');
                return;
            end
            
            % Done accumulating data, calculate the results.
            prePts = round(obj.preTime*1e-3*sampleRate);
            stimStart = prePts + 1;
            stimEnd = round((obj.preTime+obj.stimTime)*1e-3*sampleRate);
            
            % Mean data.
            data = obj.cumulativeData / double(obj.numEpochsCompleted);
            
            % Calculate baseline current before step.
            baseline = mean(data(1:prePts));
            
            % Curve fit the transient with a single exponential.
            [~, peakPt] = max(data(stimStart:stimEnd));
            
            fitStartPt = stimStart + peakPt - 1;
            fitEndPt = stimEnd;
            
            sampleInterval = 1 / sampleRate * 1e3; % ms
            
            fitTime = (fitStartPt:fitEndPt) * sampleInterval;
            fitData = data(fitStartPt:fitEndPt);
            
            % Make sure you're dealing with rows.
            fitTime = fitTime(:)';
            fitData = fitData(:)';
            
            % Initial guess for a, b, and c.
            p0 = [max(fitData) - min(fitData), (max(fitTime) - min(fitTime)) / 2, mean(fitData)];

            % Define the fit function.
            fitFunc = @(a,b,c,x) a*exp(-x/b)+c;

            curve = fit(fitTime', fitData', fitFunc, 'StartPoint', p0);

            tauCharge = curve.b;
            currentSS = curve.c;

            % Extrapolate single exponential back to where the step started to calculate the series resistance.
            current0 = curve(stimStart * sampleInterval) - baseline;
            
            rSeries = (0.005 / (current0 * 1e-12)) / 1e6;
            
            % Calculate charge, capacitance, and input resistance.
            subtractStartPt = stimStart;
            subtractEndPt = stimEnd;
            
            subtractStartTime = subtractStartPt * sampleInterval;
            subtractTime = (subtractStartPt:subtractEndPt) * sampleInterval;
            subtractData = baseline + (currentSS - baseline) * (1 - exp(-(subtractTime - subtractStartTime) / tauCharge));
            
            charge = trapz(subtractTime, data(subtractStartPt:subtractEndPt)) - trapz(subtractTime, subtractData);
            
            capacitance = charge / obj.pulseAmplitude;
            rInput = (obj.pulseAmplitude * 1e-3) / ((currentSS - baseline) * 1e-12) / 1e6;
            
            % Display results.
            text(axesHandle, 0.5, 0.5, ...
                {['R_{in} = ' num2str(rInput) ' MOhm']; ...
                ['R_{s} = ' num2str(rSeries) ' MOhm']; ...
                ['R_{m} = ' num2str(rInput - rSeries) ' MOhm']; ...
                ['R_{\tau} = ' num2str(tauCharge / (capacitance * 1e-12) / 1e9) ' MOhm']; ...
                ['C_{m} = ' num2str(capacitance) ' pF']; ...
                ['\tau = ' num2str(tauCharge) ' ms']} ...
                , 'FontSize', 20, 'HorizontalAlignment', 'center');
            
            % Save the values to the last epoch. This will be attached to
            % the epoch group later on.
            try %#ok<TRYNC>
                epoch.addParameter('rInput', rInput);
                epoch.addParameter('rSeries', rSeries);
                epoch.addParameter('rMembrane', rInput - rSeries);
                epoch.addParameter('rTau', tauCharge / (capacitance * 1e-12) / 1e9);
                epoch.addParameter('capacitance', capacitance);
                epoch.addParameter('tau_msec', tauCharge);
            end
        end
        
        function stim = createAmpStimulus(obj)
            gen = symphonyui.builtin.stimuli.PulseGenerator();
            
            gen.preTime = obj.preTime;
            gen.stimTime = obj.stimTime;
            gen.tailTime = obj.tailTime;
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
            gen.amplitude = obj.amp2PulseAmplitude;
            gen.mean = obj.rig.getDevice(obj.amp2).background.quantity;
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice(obj.amp2).background.displayUnits;
            
            stim = gen.generate();
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);
            
            epoch.addStimulus(obj.rig.getDevice(obj.amp), obj.createAmpStimulus());
            epoch.addResponse(obj.rig.getDevice(obj.amp));
            
            if numel(obj.rig.getDeviceNames('Amp')) >= 2
                epoch.addStimulus(obj.rig.getDevice(obj.amp2), obj.createAmp2Stimulus());
                epoch.addResponse(obj.rig.getDevice(obj.amp2));
            end
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