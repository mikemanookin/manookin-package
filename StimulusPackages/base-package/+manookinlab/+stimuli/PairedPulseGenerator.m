classdef PairedPulseGenerator < symphonyui.core.StimulusGenerator
    % Generates a single rectangular pulse stimulus.
    
    properties
        preTime     % Leading duration (ms)
        pulse1Time  % Pulse1 duration (ms)
        interTime   % Interpulse duration (ms)
        pulse2Time  % Pulse2 duration (ms)
        tailTime    % Trailing duration (ms)
        pulse1Amplitude   % Pulse1 amplitude (units)
        pulse2Amplitude   % Pulse2 amplitude (units)
        mean        % Mean amplitude (units)
        sampleRate  % Sample rate of generated stimulus (Hz)
        units       % Units of generated stimulus
    end
    
    methods
        
        function obj = PairedPulseGenerator(map)
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
            pulse1Pts = timeToPts(obj.pulse1Time);
            interPts = timeToPts(obj.interTime);
            pulse2Pts = timeToPts(obj.pulse2Time);
            tailPts = timeToPts(obj.tailTime);
            
            data = ones(1, prePts + pulse1Pts + interPts + pulse2Pts + tailPts) * obj.mean;
            data(prePts + (1 : pulse1Pts)) = obj.pulse1Amplitude + obj.mean;
            data(prePts + pulse1Pts + interPts + (1 : pulse2Pts)) = obj.pulse2Amplitude + obj.mean;
            
            parameters = obj.dictionaryFromMap(obj.propertyMap);
            measurements = Measurement.FromArray(data, obj.units);
            rate = Measurement(obj.sampleRate, 'Hz');
            output = OutputData(measurements, rate);
            
            cobj = RenderedStimulus(class(obj), parameters, output);
            s = symphonyui.core.Stimulus(cobj);
        end
        
    end
    
end

