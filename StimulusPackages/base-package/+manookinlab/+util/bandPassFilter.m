function Xfilt = bandPassFilter(X,low,high,SampleInterval)
%this is not really correct
Xfilt = lowPassFilter(highPassFilter(X,low,SampleInterval),...
    high,SampleInterval);
