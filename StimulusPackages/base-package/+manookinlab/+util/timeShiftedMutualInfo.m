function [information, t] = timeShiftedMutualInfo(S, R, binWidth, windowHalfWidth, numStates)
% [information, t] = timeShiftedMutualInfo(S, R, binWidth, windowHalfWidth, numStates)
%
% Compute the time-shifted mutual information between stimulus and
% response.
% 
% Inputs: 
%   S : stimulus matrix (trials x time)
%   R : response matrix (trials x time)
%   binWidth : response bin rate in msec
%   windowHalfWidth : half-width of window for computing mutual information
%       (in samples)
%   numStates : number of stimulus states used for cond. probability 

if nargin < 5
    numStates = 10;
end

% Sort the stimulus levels.
sS = sort(S(:))';

% Bin into discrete stimulus levels
valsPerBin = floor(length(sS) / numStates);
levels = [ sS(1 : valsPerBin : end) inf ]; 
sSort = S;
for k = 1 : length(levels)-1
    sSort(S >= levels(k) & S < levels(k+1)) = k;
end

%--------------------------------------------------------------------------
% Calculate the information from the past.
pastInfo = zeros(1,windowHalfWidth+1);
count = windowHalfWidth+2;
for i = 1 : windowHalfWidth+1 
    x = R(:,(i-1)+windowHalfWidth+1:size(R,2)-windowHalfWidth+(i-1))'; 
    y = sSort(:,windowHalfWidth+1:size(sSort,2)-windowHalfWidth)';
    
    % Calculate the conditional probabilities.
    [N, ~] = hist3([x(:), y(:)]);
    
    % Probability of observing a stimulus.
    pX = sum(N,1) / sum(sum(N)); 
    % Probability of observing a response/word.
    pW = sum(N,2) / sum(sum(N)); 
    % Probability of observing a stimulus given a response/word.
    pXW = N / sum(sum(N));
    
    % Compute the information
    itmp = zeros(length(pX),length(pW));
    for j = 1 : length(pX)
        for k = 1 : length(pW)
            itmp(k,j) = pXW(k,j) * log( pXW(k,j) / (pW(k)*pX(j)) ) / log(2) / (binWidth*1e-3);
        end
    end
    % Decrement the count
    count = count - 1;
    
    % Sum
    pastInfo(count) = nansum(itmp(:));
end

%--------------------------------------------------------------------------
% Calculate the future information
futureInfo = zeros(1,windowHalfWidth);
count=0;

for i = 1:windowHalfWidth
    x = R(:,windowHalfWidth+1-i:size(R,2)-windowHalfWidth-i)';
    y = sSort(:,windowHalfWidth+1:size(sSort,2)-windowHalfWidth)';
    
    % Calculate the conditional probabilities.
    [N, ~] = hist3([x(:), y(:)]);
    
    % Probability of observing a stimulus.
    pX = sum(N,1) / sum(sum(N)); 
    % Probability of observing a response/word.
    pW = sum(N,2) / sum(sum(N)); 
    % Probability of observing a stimulus given a response/word.
    pXW = N / sum(sum(N));
    
    % Compute the mutual information
    itmp = zeros(length(pX),length(pW));
    for j=1:length(pX)
        for k=1:length(pW)
            itmp(k,j) = pXW(k,j) * log( pXW(k,j)/ (pW(k)*pX(j)) )/log(2)/(binWidth * 1e-3);
        end
    end
    
    % Increment the count
    count = count + 1;
    
    % Sum
    futureInfo(count) = nansum(itmp(:));
end

% Concatenate the past and future information.
information = [pastInfo futureInfo];

% Get the time trajectory (in msec).
t = (-windowHalfWidth : windowHalfWidth) * binWidth;
