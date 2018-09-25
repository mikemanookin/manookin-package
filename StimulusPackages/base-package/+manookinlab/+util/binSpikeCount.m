function binnedCount = binSpikeCount(spikes, binRate, sampRate)
%BINSPIKECOUNT

[trialLngth, numRepeats] = size(spikes);

if (trialLngth == 1 && numRepeats > 1)
    spikes = spikes';
    trialLngth = numRepeats;
    numRepeats = 1;
end

binSize=sampRate/binRate;
numBins=floor(trialLngth/binSize);
% Bin the spike rate.
binnedCount = zeros(numBins,numRepeats);
for j=1:numBins
    index = round(binSize*(j-1)) + 1: round(j*binSize);
    binnedCount(j,:) = sum(spikes(index,:),1);
end