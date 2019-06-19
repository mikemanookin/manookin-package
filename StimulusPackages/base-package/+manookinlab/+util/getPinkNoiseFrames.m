function frameValues = getPinkNoiseFrames(numXChecks, numYChecks, numFrames, noiseContrast, spatialPower, temporalPower, seed)
% frameValues = getPinkNoiseFrames(numXChecks, numYChecks, numFrames, noiseContrast, spatialPower, temporalPower, seed)


% Seed the random number generator.
noiseStream = RandStream('mt19937ar','Seed',seed);

x = [(0:floor(numXChecks/2)) -(ceil(numXChecks/2)-1:-1:1)]'/numXChecks;
% Reproduce these frequencies along ever row
x = repmat(x,1,numYChecks);
% v is the set of frequencies along the second dimension.  For a square
% region it will be the transpose of u
y = [(0:floor(numYChecks/2)) -(ceil(numYChecks/2)-1:-1:1)]/numXChecks;
% Reproduce these frequencies along ever column
y = repmat(y,numXChecks,1);

% Get the temporal frequencies.
t = [(0:floor(numFrames/2)) -(ceil(numFrames/2)-1:-1:1)]'/numFrames;

% Generate the power spectrum
sf = (x.^2 + y.^2).^(-spatialPower/2);

% Set any infinities to zero
sf(sf == inf) = 0;

tf = (t.^2).^(-temporalPower/2);
tf(tf == inf) = 0;

z = reshape(sf,[numel(sf),1]) * tf(:)';

% Generate random phase shifts.
phi = noiseStream.randn(size(z));

% Inverse Fourier transform to obtain the the spatial pattern
frameValues = ifft2(z.^0.5 .* (cos(2*pi*phi)+1i*sin(2*pi*phi)));
frameValues = real(frameValues);

% frameValues = reshape(frameValues,[numFrames,numYChecks,numXChecks]);
frameValues = reshape(frameValues',[numFrames,numYChecks,numXChecks]);

frameValues = noiseContrast * frameValues / std(frameValues(:));
frameValues(frameValues > 1) = 1;
frameValues(frameValues < -1) = -1;

