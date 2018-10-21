function [spikes, spikeTimes] = ThresholdDetection(fdata, threshold)
% THRESHOLDDETECTION.m Calculates the spike matrix based on a simple spike
% thresholding.
%
% INPUTS:
%   fdata: filtered raw data
%   threshold: the spike threshold
%
% OUTPUT:
%   spikes: output array of spikes
%
% spikes = ThresholdDetection(fdata, threshold)
%

% Initialize the spikes array.
spikes = zeros(size(fdata));

% Subtract the offset.
fdata = fdata - median(fdata);

if threshold == 0
    % Standard measure of spike threshold.
%     threshold = 3 * std(fdata);
    threshold = 4 * median(abs(fdata))/0.6745;
    if -mean(fdata(fdata < 0)) > mean(fdata(fdata > 0))
        threshold = -threshold;
    end
end

if threshold > 0
    [spikeAmps,spikeTimes] = getPeaks(fdata,1);
    spikeTimes(spikeAmps < threshold) = [];
else
    [spikeAmps,spikeTimes] = getPeaks(fdata,-1);
    spikeTimes(spikeAmps > threshold) = [];
end

% % Shift the data for comparison with unshifted data.
% dataOriginal = fdata(1:end-1);
% dataShifted = fdata(2:end);
% 
% % Look for threshold crosses.
% if (threshold > 0)
%     spikeTimes = find(dataOriginal < threshold & dataShifted > threshold) + 1;
% else
%     spikeTimes = find(dataOriginal > threshold & dataShifted < threshold) + 1;
% end

% Assign the spike times a value of 1; all else is 0.
if ~isempty(spikeTimes)
    spikes(spikeTimes) = 1;
end





