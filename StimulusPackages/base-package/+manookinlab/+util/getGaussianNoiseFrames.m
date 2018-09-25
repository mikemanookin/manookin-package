function frameValues = getGaussianNoiseFrames(numFrames, frameDwell, stdev, seed)

% Seed the random number generator.
noiseStream = RandStream('mt19937ar', 'Seed', seed);

frameValues = stdev*noiseStream.randn(numFrames, 1);

if frameDwell > 1
    frameValues = ones(frameDwell,1)*frameValues(:)';
end

frameValues = frameValues(:);