classdef ChirpGenerator < symphonyui.core.StimulusGenerator
    properties
        preTime             % Leading duration (ms)
        tailTime            % Trailing duration (ms)
        stepTime
        frequencyTime
        contrastTime
        interTime
        mean                % Stimulus mean (V)
        stepContrast           % Stimulus peak amplitude.
        frequencyContrast
        frequencyMin = 0.0              % Minimum temporal frequency (Hz)
        frequencyMax = 10.0             % Maximum temporal frequency (Hz)
        chirpRate           % Chirp rate (Hz/sec).
        invertRate          % Invert the rate to high frequencies?
        sampleRate          % Sample rate of generated stimulus (Hz)
        units               % Units of generated stimulus
    end
    
    methods
        
        function obj = ChirpGenerator(map)
            if nargin < 1
                map = containers.Map();
            end
            obj@symphonyui.core.StimulusGenerator(map);
        end
        
    end
    
    methods (Access = protected)
        
        function s = generateStimulus(obj)
            import Symphony.Core.*;
            
            timeToPts = @(t)(round(t / 1e3 * obj.sampleRate));
            
            prePts = timeToPts(obj.preTime);
            tailPts = timeToPts(obj.tailTime);
            stepPts = timeToPts(obj.stepTime);
            frequencyPts = timeToPts(obj.frequencyTime);
            contrastPts = timeToPts(obj.contrastTime);
            interPts = timeToPts(obj.interTime);
            
            stimPts = interPts*3 + stepPts*2 + frequencyPts + contrastPts;
            
            % Get the time axis for your stimulus.
            t = (0 : stimPts-1)/obj.sampleRate;
            
            % Generate the chirp stimulus.
            noiseTime = chirp(t, 0, 1, obj.chirpRate, 'linear', -90);
            
            % Create your stimulus data.
            data = zeros(1, prePts + stimPts + tailPts);
%             data = ones(1, prePts + stimPts + tailPts) * obj.mean;
            
            % Get the pulses
            data(prePts+(1:stepPts)) = obj.stepContrast;
            data(prePts+interPts+(1:stepPts)) = -obj.stepContrast;
            
            % Frequency series.
            frequencyDelta = (obj.frequencyMax - obj.frequencyMin)/(frequencyPts/obj.sampleRate)/2;
            t = (0 : frequencyPts-1)/obj.sampleRate;
            data(prePts+interPts+(1:frequencyPts)) = obj.frequencyContrast*sin(2*pi*(obj.frequencyMin*t+frequencyDelta*t.^2));
            
            data(prePts + 1:prePts + stimPts) = noiseTime + obj.mean;
            
            % Multiply by the amplitdue.
            data = obj.amplitude * data;
            
            % Invert to high-frequencies first.
            if obj.invertRate
                data = fliplr(data);
            end
            
            parameters = obj.dictionaryFromMap(obj.propertyMap);
            measurements = Measurement.FromArray(data, obj.units);
            rate = Measurement(obj.sampleRate, 'Hz');
            output = OutputData(measurements, rate);
            
            cobj = RenderedStimulus(class(obj), parameters, output);
            s = symphonyui.core.Stimulus(cobj);
        end
        
    end
end