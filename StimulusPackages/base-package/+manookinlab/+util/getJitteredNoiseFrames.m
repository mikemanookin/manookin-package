function frameValues = getJitteredNoiseFrames(numXStixels, numYStixels, numXChecks, numYChecks, numFrames, stepsPerStixel, seed, frameDwell)
% 
% stepsPerStixel = 4;
% % 
% % % obj.canvasSize = [1140,912];
% % % obj.stixelSize=100;
% % % obj.numXStixels = ceil(obj.canvasSize(1)/obj.stixelSize)+1;
% % % obj.numYStixels = ceil(obj.canvasSize(2)/obj.stixelSize)+1;
% % % obj.numXChecks = ceil(obj.canvasSize(1)/(obj.stixelSize/stepsPerStixel));
% % % obj.numYChecks = ceil(obj.canvasSize(2)/(obj.stixelSize/stepsPerStixel));
% % 
% % numYStixels = 11;
% % numXStixels = 13;
% % numXChecks = 46;
% % numYChecks = 37;
% % numFrames = 120;
% % seed = 1;
% 
% numXStixels = 10 + 1;
% numYStixels = 12 + 1;
% numXChecks = 40;
% numYChecks = 48;
% numFrames = 120;
% seed = 1;

if ~exist('frameDwell','var')
    frameDwell = 1;
end

frameDwell = double(frameDwell);

% Seed the random number generator.
noiseStream = RandStream('mt19937ar', 'Seed', seed);

% Generate the larger grid of stixels.
gridValues = 2*(noiseStream.rand(numYStixels,numXStixels,ceil(numFrames/frameDwell)) > 0.5)-1;
% Replicate/expand the grid along the spatial dimensions.
fullGrid = zeros(numYStixels*stepsPerStixel,numXStixels*stepsPerStixel,ceil(numFrames/frameDwell));
for k = 1 : numYStixels*stepsPerStixel
    yindex = ceil(k/stepsPerStixel);
    for m = 1 : numXStixels*stepsPerStixel
        xindex = ceil(m/stepsPerStixel);
        fullGrid(k,m,:) = gridValues(yindex,xindex,:);
    end
end

% Generate the motion trajectory of the larger stixels.
noiseStream = RandStream('mt19937ar', 'Seed', seed); % reseed
xSteps = round((stepsPerStixel-1)*noiseStream.rand(1,ceil(numFrames/frameDwell)));
ySteps = round((stepsPerStixel-1)*noiseStream.rand(1,ceil(numFrames/frameDwell)));

% Get the frame values for the finer grid.
frameValues = zeros(numYChecks,numXChecks,numFrames);
for k = 1 : numFrames
    tidx = ceil(k/frameDwell);
    frameValues(:,:,k) = fullGrid((1:numYChecks)+ySteps(tidx),(1:numXChecks)+xSteps(tidx), tidx);
end


