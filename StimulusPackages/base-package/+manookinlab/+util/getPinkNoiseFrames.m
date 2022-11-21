function frameValues = getPinkNoiseFrames(numXChecks, numYChecks, numFrames, noiseContrast, spatialAmplitude, temporalAmplitude, chromaticClass, seed)
% frameValues = getPinkNoiseFrames(numXChecks, numYChecks, numFrames, noiseContrast, spatialAmplitude, temporalAmplitude, seed)


% % Find the length of the temporal filter.
% f_length = ceil(7 * tau_frames);
% % Make sure it's an odd number.
% if mod(f_length,2) == 1
%     f_length = f_length + 1;
% end

% Seed the random number generator.
noiseStream = RandStream('mt19937ar','Seed',seed);

x = [(0:floor(numXChecks/2)) -(ceil(numXChecks/2)-1:-1:1)]'/numXChecks;
x = abs(x);
% Reproduce these frequencies along ever row
x = repmat(x,1,numYChecks);
% v is the set of frequencies along the second dimension.  For a square
% region it will be the transpose of u
y = [(0:floor(numYChecks/2)) -(ceil(numYChecks/2)-1:-1:1)]/numXChecks;
y = abs(y);
% Reproduce these frequencies along ever column
y = repmat(y,numXChecks,1);

% Get the temporal frequencies.
t = [(0:floor(numFrames/2)) -(ceil(numFrames/2)-1:-1:1)]'/numFrames;
t = abs(t);
tf = t .^ -temporalAmplitude;
tf(tf == inf) = 0;
tf = tf * 0.5;
tf(1) = 1;


% Generate the Amplitude spectrum
sf = (x.^2 + y.^2) .^ -(spatialAmplitude/2);
sf = sf';

% Set any infinities to zero
sf(sf == inf) = 0;

% Scale to make sure that the highest frequency is the Nyquist limit.
sf = sf * 0.5;

st_f = sf(:) * tf';
st_f = reshape(st_f,[numYChecks,numXChecks,numFrames]);

if strcmpi(chromaticClass,'RGB')
    st_f = repmat(st_f,[1,1,1,3]);
elseif strcmpi(chromaticClass,'BY')
    st_f = repmat(st_f,[1,1,1,2]);
end

phi = noiseStream.rand(size(st_f));

% Generate the noise sequence.
frameValues = ifftn(st_f .* (cos(2*pi*phi)+1i*sin(2*pi*phi)));
frameValues = real(frameValues);

if strcmpi(chromaticClass,'BY')
    frameValues(:,:,:,3) = frameValues(:,:,:,2);
    frameValues(:,:,:,2) = frameValues(:,:,:,1);
end

% sf = repmat(sf,[1, 1, numFrames + f_length]);

% sf = repmat(sf,[1, 1, numFrames]);
% 
% % Generate a matrix of random phase shifts
% phi = noiseStream.rand(size(sf));
% 
% % Generate the noise sequence.
% phi = ifftn(sf.^0.5 .* (cos(2*pi*phi)+1i*sin(2*pi*phi)));
% phi = real(phi);
% 
% % Get the temporal weights.
% % t_weights = fliplr( exp(-( 0:f_length-1)/tau_frames ) );
% t_weights = exp(-( linspace(-(f_length-1)/2,(f_length-1)/2,f_length).^2/(2*tau_frames^2)) );
% t_weights = t_weights / sum(t_weights);
% frameValues = zeros(numXChecks, numYChecks, numFrames);
% for jj = 1 : f_length
%     frameValues = frameValues + t_weights(jj)*phi(:,:,(1:numFrames)+jj-1);
% end

frameValues = noiseContrast * frameValues / std(frameValues(:));
frameValues(frameValues > 1) = 1;
frameValues(frameValues < -1) = -1;

%% Sanity checks...
% [x2, y2] = meshgrid(linspace(-960,960,numYChecks),linspace(-1280,1280,numXChecks));
% r = sqrt(x2.^2 + y2.^2);
% 
% strf
% 
% ft = fft(frameValues,[],3);
% ft = squeeze(mean(abs(ft),[1,2]));

