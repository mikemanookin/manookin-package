function Xfilt = lowPassFilter(X,F,SampleInterval)
%F is in Hz
%Sample interval is in seconds
%X is a vector or a matrix of row vectors

L = size(X,2);
if L == 1 %flip if given a column vector
    X=X'; 
    L = size(X,2);
end

nfact = floor(L/2);  % length of edge transients
% Extrapolate data at ends to get rid of edge effects during filtering.
X = [X((nfact+1):-1:1),X,X((L-2):-1:L-nfact)];
% X = [2*X(1)-X((nfact+1):-1:2),X,2*X(L)-X((L-1):-1:L-nfact)];

FreqStepSize = 1/(SampleInterval * L);
FreqCutoffPts = round(F / FreqStepSize);

% eliminate frequencies beyond cutoff (middle of matrix given fft
% representation)
FFTData = fft(X, [], 2);
FFTData(:,FreqCutoffPts:size(FFTData,2)-FreqCutoffPts) = 0;
Xfilt = real(ifft(FFTData, [], 2));

% remove extrapolated pieces of y
Xfilt([1:nfact L+nfact+(1:nfact)]) = [];

% Wn = F*SampleInterval; %normalized frequency cutoff
% [z, p, k] = butter(1,Wn,'low');
% [sos,g]=zp2sos(z,p,k);
% myfilt=dfilt.df2sos(sos,g);
% Xfilt = filter(myfilt,X');
% Xfilt = Xfilt';	

