function frames = getMotionNoiseFrames(numXChecks, numYChecks, numFrames, v, seed, frameRate, noiseCorrelation)
%
%
%
% Based on Pitkow & Meister (2012). Decorrelation and efficient coding by
% retinal ganglion cells. Nat Neuroscience 15(4):628-35.

if ~exist('noiseCorrelation', 'var')
    noiseCorrelation = 2;
end

% Make sure you have enough frames.
actualFrames = numFrames;
numFrames = max(numFrames, 1000);

% Define the time axis.
t = (1:numFrames)/frameRate;
% Get the time constant.
tau = frameRate ./ v;

% Get the filter pad points.
padPts = 200;

N = max(numXChecks, numYChecks);

% k = -N/2:N/2-1; % spatial frequencies in the image
% 
% myP = 1./abs(k).^2 .* ( (1 - exp(-2*abs(k)))) ./ ((1 + exp(-2*abs(k))) - 2*exp(-2*abs(k)));
% myP(N/2+1:N) = myP(1:N/2);
% myP(1:N/2) = fliplr(myP(1:N/2));
% myP = sqrt(myP);
% myP = (myP' * myP);

k = [(0 : floor(N/2)) -(ceil(N/2)-1:-1:1)]'/N;
k = repmat(k, 1, N);
myP = (k.^2 + (k').^2).^(-noiseCorrelation/2);
myP(myP == inf) = 0;

% Seed the random number generator.
noiseStream = RandStream('mt19937ar', 'Seed', seed);

frames = zeros(N,N,numFrames);
for b = 1 : numFrames
    phi = noiseStream.randn(N);
%     frames(:,:,b) = ifft2( fft2( myP ) .* fft2( noiseStream.randn(N) ) );
    frames(:,:,b) = real(ifft2( myP.^0.5 .* cos(2*pi*phi)+1i*sin(2*pi*phi) ));
end

tFilt1 = exp(-([fliplr(-t(1:padPts)), t]).^2/tau(1)); tFilt1 = tFilt1/max(tFilt1);

for b = 1 : N
    for c = 1 : N
        tmp1 = conv(tFilt1',squeeze(frames(b,c,:)));
%         tmp1 = ifft( fft([zeros(padPts,1); squeeze(frames(b,c,:))]) .* fft(tFilt1') );
        frames(b,c,:) = tmp1(padPts+(1:numFrames)); 
    end
end

frames = real(frames);

% Grab the X/Y frames that you need.
frames = frames(1:numYChecks,1:numXChecks,1:actualFrames);

frames = frames / std(frames(:)) * 0.35;

frames(frames > 1) = 1;
frames(frames < -1) = -1;
