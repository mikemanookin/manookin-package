function binnedRate = BinSpikeRate(spikes, binRate, sampRate)
%BINSPIKERATE

[trialLngth, numRepeats] = size(spikes);

if (trialLngth == 1 && numRepeats > 1)
    spikes = spikes';
    trialLngth = numRepeats;
    numRepeats = 1;
end

% Convert to spike rate.
spikes = spikes * sampRate;

binSize=sampRate/binRate;
numBins=floor(trialLngth/binSize);
% Bin the spike rate.
binnedRate = zeros(numBins,numRepeats);
for j=1:numBins
    index = round(binSize*(j-1)) + 1: round(j*binSize);
    binnedRate(j,:) = mean(spikes(index,:),1);
end