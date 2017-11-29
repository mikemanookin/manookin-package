classdef ChirpGenerator < symphonyui.core.StimulusGenerator
    properties
        preTime             % Leading duration (ms)
        stimTime            % Stimulus duration (ms)
        tailTime            % Trailing duration (ms)
        mean                % Stimulus mean (pA)
        amplitude           % Stimulus peak amplitude.
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
            stimPts = timeToPts(obj.stimTime);
            tailPts = timeToPts(obj.tailTime);
            
            % Get the time axis for your stimulus.
            t = (0 : stimPts-1)/obj.sampleRate;
            
            % Generate the chirp stimulus.
            noiseTime = chirp(t, 0, 1, obj.chirpRate, 'linear', -90);
            
            % Create your stimulus data.
            data = ones(1, prePts + stimPts + tailPts) * obj.mean;
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