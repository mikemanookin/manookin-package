function frameValues = getUniformNoiseFrames(numFrames, frameDwell, ct, seed)

% Seed the random number generator.
noiseStream = RandStream('mt19937ar', 'Seed', seed);

frameValues = ct*(2*noiseStream.rand(numFrames, 1)-1);

if frameDwell > 1
    frameValues = ones(frameDwell,1)*frameValues(:)';
end

frameValues = frameValues(:);