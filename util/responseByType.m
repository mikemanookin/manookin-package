function [response, leak, spikeTimes, spikeAmps] = responseByType(response, onlineAnalysis, preTime, sampleRate, varargin)

ip = inputParser();
ip.addParameter('threshold',-20.0, @(x)isfloat(x));
ip.addParameter('spikeAnalysis', 'k-means', @(x)ischar(x));
ip.parse(varargin{:});

spikeAnalysis = ip.Results.spikeAnalysis;
threshold = ip.Results.threshold;

leak = 0;
spikeTimes = [];
spikeAmps = [];

switch onlineAnalysis
    case 'extracellular'
        response = wavefilter(response(:)', 6);
        if strcmpi(spikeAnalysis, 'k-means')
%             try
%                 S.sp = SpikeDetector(response);
%             catch
                S = spikeDetectorOnline(response); 
%                 S.sp(S.spikeAmps > 30) = [];
%             end
%             S.sp = getSpikeParameters(response,S.sp,sampleRate);
            spikesBinary = zeros(size(response));
            if ~isempty(S.sp)
                spikesBinary(S.sp) = 1;
                spikeTimes = S.sp;
                spikeAmps = S.spikeAmps;
            end
            
        else
            [spikesBinary, spikeTimes, spikeAmps] = ThresholdDetection(response, threshold);
        end
        response = spikesBinary * sampleRate;
    case 'spikes_CClamp'
        spikeTimes = getThresCross([0 diff(response(:)')], 1.5, 1);
        spikesBinary = zeros(size(response));
        spikesBinary(spikeTimes) = 1;
        response = spikesBinary * sampleRate;
    case 'subthresh_CClamp'
        spikeTimes = getThresCross([0 diff(response(:)')], 1.5, 1);
        % Get the subthreshold potential.
        if ~isempty(spikeTimes)
            response = getSubthreshold(response(:)', spikeTimes);
        else
            response = response(:)';
        end

        % Subtract the median.
        if preTime > 0
            leak = median(response(1:round(sampleRate*preTime/1000)));
        else
            leak = median(response);
        end
        response = response - leak;
    otherwise
        % Subtract the median.
        if preTime > 0
            leak = median(response(1:round(sampleRate*preTime/1000)));
        else
            leak = median(response);
        end
        response = response - leak;
        
        % Check for 60 cycle noise.
        F = sampleRate*(0:length(response)/2-1)/length(response); % Frequency.
        index60 = find(abs(F-60) == min(abs(F-60)),1);
        A = abs(fft(response));
        % Get the average amplitude around 60 Hz.
        avgN = mean(A([index60-10:index60-2, index60+2:index60+10]));
        if A(index60)/avgN > 3
            d = designfilt('bandstopiir','FilterOrder',2, ...
               'HalfPowerFrequency1',59,'HalfPowerFrequency2',61, ...
               'DesignMethod','butter','SampleRate',sampleRate);

%             response = filtfilt(d,response);
        end
end