function d = binData(data, binRate, sampleRate)

binSize = sampleRate / binRate;
numBins = floor(length(data)/binSize);

d = zeros(1, numBins);
for k = 1 : numBins
    index = round(binSize*(k-1))+1 : round(binSize*k);
    d(k) = mean(data(index));
end




