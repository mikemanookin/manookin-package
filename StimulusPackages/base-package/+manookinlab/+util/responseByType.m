function [response, leak] = responseByType(response, onlineAnalysis, preTime, sampleRate, varargin)

ip = inputParser();
ip.addParameter('threshold',-20.0, @(x)isfloat(x));
ip.addParameter('spikeAnalysis', 'k-means', @(x)ischar(x));
ip.parse(varargin{:});

spikeAnalysis = ip.Results.spikeAnalysis;
threshold = ip.Results.threshold;

leak = 0;

switch onlineAnalysis
    case 'extracellular'
        response = manookinlab.util.DB4Filter(response(:)', 6);
        if strcmpi(spikeAnalysis, 'k-means')
%             try
%                 S.sp = SpikeDetector(response);
%             catch
                S = manookinlab.util.spikeDetectorOnline(response);  
%             end
%             S.sp = getSpikeParameters(response,S.sp,sampleRate);
            spikesBinary = zeros(size(response));
            if ~isempty(S.sp)
                spikesBinary(S.sp) = 1;
            end
        else
            spikesBinary = manookinlab.util.ThresholdDetection(response, threshold);
        end
        response = spikesBinary * sampleRate;
    case 'spikes_CClamp'
        spikeTimes = manookinlab.util.getThresCross([0 diff(response(:)')], 1.5, 1);
        spikesBinary = zeros(size(response));
        spikesBinary(spikeTimes) = 1;
        response = spikesBinary * sampleRate;
    case 'subthresh_CClamp'
        spikeTimes = manookinlab.util.getThresCross([0 diff(response(:)')], 1.5, 1);
        % Get the subthreshold potential.
        if ~isempty(spikeTimes)
            response = manookinlab.util.getSubthreshold(response(:)', spikeTimes);
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
end