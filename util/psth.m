function y = psth(y, filterSigma, sampleRate, downsamp)

if nargin == 3
    downsamp = 1;
elseif nargin == 2
    sampleRate = 10000;
    downsamp = 1;
elseif nargin == 1
    filterSigma = 15;
    sampleRate = 10000;
    downsamp = 1;
end


filterSigma = (filterSigma/1000)*sampleRate; %15 msec -> dataPts
newFilt = normpdf(1:10*filterSigma,10*filterSigma/2,filterSigma);
if max(y(:)) == 1
    y = sampleRate*y;
end
y = conv(y(:)',newFilt,'same');
if downsamp > 1
    y = decimate(y, downsamp);
end