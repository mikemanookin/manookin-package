function [psdx,freq] = getPowerSpectrum(x, sampleRate)


%[vx,fx] = periodogram(x',[],[],10000);
% [vx,fx] = periodogram(x,hamming(size(x,1)),[],10000);

N = size(x,2);
xdft = mean(fft(x,[],2));
xdft = xdft(1:N/2+1);
psdx = (1/(sampleRate*N)) * abs(xdft).^2;
psdx(2:end-1) = 2*psdx(2:end-1);
freq = 0 : sampleRate/N : sampleRate/2;