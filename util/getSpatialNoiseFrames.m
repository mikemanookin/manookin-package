function frameValues = getSpatialNoiseFrames(numXChecks, numYChecks, numFrames, noiseClass, chromaticClass, seed)

% Seed the random number generator.
noiseStream = RandStream('mt19937ar', 'Seed', seed);

% Deal with the noise type.
if strcmpi(noiseClass, 'binary')
    if strcmpi(chromaticClass, 'RGB')
        frameValues = noiseStream.rand(numFrames,numYChecks,numXChecks,3) > 0.5;
    else
        frameValues = noiseStream.rand(numFrames, numYChecks,numXChecks) > 0.5;
    end
    frameValues = 2*frameValues-1;
elseif strcmpi(noiseClass, 'ternary')
    if strcmpi(chromaticClass, 'RGB')
        eta = double(noiseStream.randn(numFrames,numYChecks, numXChecks,3) > 0)*2 - 1;
        frameValues = (eta + circshift(eta, [0, 1, 1])) / 2;
    else
        eta = double(noiseStream.randn(numFrames,numYChecks, numXChecks) > 0)*2 - 1;
        frameValues = (eta + circshift(eta, [0, 1, 1])) / 2;
    end
else
    if strcmpi(chromaticClass, 'RGB')
        frameValues = (0.3*noiseStream.randn(numFrames, numYChecks, numXChecks, 3));
    else
        frameValues = (0.3*noiseStream.randn(numYChecks, numXChecks, numFrames));
        frameValues = reshape(frameValues,[numYChecks*numXChecks,numFrames])';
        frameValues = reshape(frameValues,[numFrames, numYChecks, numXChecks]);
%         frameValues = (0.3*noiseStream.randn(numFrames, numYChecks, numXChecks));
    end
end