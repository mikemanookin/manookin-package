function [vSequence, dtVec, shiftFrames] = getTernaryVelocityFrames(numXChecks, numYChecks, numStimFrames, seed, dx, frameRate)

if ~exist('frameRate','var')
    frameRate = 60;
end
sc = 2*frameRate/60;

% Seed the noise stream.
noiseStream = RandStream('mt19937ar', 'Seed', seed);

% Generate the initial random noise sequence.
eta = double(noiseStream.randn(numYChecks, numXChecks, numStimFrames) > 0)*2 - 1;

% Seed the noise stream.
noiseStream = RandStream('mt19937ar', 'Seed', seed);
% Create a sequence where the velocity changes between frames.
dtVec = abs(round(sc*noiseStream.randn(1, numStimFrames-1)));
shiftFrames = cumsum([1 dtVec+1]);
% Take only the shift indices <= stimulus frames.
ind = find((shiftFrames(1:end-1)+(dtVec+1)) <= numStimFrames);
shiftFrames = shiftFrames(ind); %#ok<FNDSB>
dtVec = dtVec(1 : length(shiftFrames));

vSequence = eta;
for k = 1 : length(shiftFrames)
    index = shiftFrames(k) + (1 : dtVec(k));
    vSequence(:,:, index) = (vSequence(:,:, index) + circshift(vSequence(:,:, index),[0, dx, dtVec(k)])) / 2;
end
index = shiftFrames(end) + dtVec(end);

% Make sure the whole stimulus is ternary.
if index < numStimFrames
    vSequence(:,:, index+1:end) = (vSequence(:,:, index+1:end) + circshift(vSequence(:,:, index+1:end),[0, dx, 0]))/2;
end

% Make the first frame ternary.
if dtVec(1) > 0
    vSequence(:,:, 1) = (vSequence(:,:, 1) + circshift(vSequence(:,:, 1),[0, dx, 0]))/2;
end