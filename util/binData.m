function d = binData(data, binRate, sampleRate)

binSize = sampleRate / binRate;
numBins = floor(length(data)/binSize);

if size(data,2) == 1
    data = data';
end

d = zeros(size(data,1), numBins);
for j = 1 : size(data,1)
    for k = 1 : numBins
        index = round(binSize*(k-1))+1 : round(binSize*k);
        d(j,k) = mean(data(j,index));
    end
end



