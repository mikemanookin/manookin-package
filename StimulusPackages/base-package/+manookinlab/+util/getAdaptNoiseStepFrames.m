function [frameSeq,frameSeqSurround,contrasts] = getAdaptNoiseStepFrames(nframes, durations, sFrames, eFrames, seed, varargin)

ip = inputParser();
ip.addParameter('maxContrast',0.35,@(x)isfloat(x));
ip.addParameter('minContrast',0.1,@(x)isfloat(x));
ip.addParameter('noiseClass','gaussian',@(x)ischar(x));
ip.addParameter('stimulusClass','full-field',@(x)ischar(x));
ip.parse(varargin{:});

maxContrast = ip.Results.maxContrast;
minContrast = ip.Results.minContrast;
noiseClass = ip.Results.noiseClass;
stimulusClass = ip.Results.stimulusClass;

frameSeqSurround = [];


% Seed the random number generator.
noiseStream = RandStream('mt19937ar', 'Seed', seed);

% Get the contrast series. [0.05 to 0.35 RMS contrast]
contrasts = (maxContrast-minContrast)*noiseStream.rand(1, length(durations)) + minContrast;

% Re-seed the random number generator.
noiseStream = RandStream('mt19937ar', 'Seed', seed);

% Pre-generate frames for the epoch.
% nframes = stimTime*1e-3*frameRate + ceil(1.5*stimTime*1e-3); 
% eFrames = cumsum(durations*1e-3*frameRate);
% sFrames = [0 eFrames(1:end-1)]+1;
% eFrames(end) = nframes;

% Generate the raw sequence.
if strcmp(noiseClass, 'binary')
    frameSeq = 2 * (noiseStream.rand(1,nframes)>0.5) - 1;
else
    frameSeq = noiseStream.randn(1,nframes);
end

% Assign appropriate contrasts to the frame blocks.
% for k = 1 : length(sFrames)
%     frameSeq(sFrames(k) : eFrames(k)) = frameSeq(sFrames(k) : eFrames(k)) * contrasts(k);
% end
% frameSeq(frameSeq < -1) = -1;
% frameSeq(frameSeq > 1) = 1;

if strcmp(stimulusClass,'center-const-surround')
    frameSeq = min(contrasts)*frameSeq;
    frameSeqSurround = zeros(size(frameSeq));
    highInd = find(contrasts == max(contrasts),1);
    % Reseed the generator.
    noiseStream = RandStream('mt19937ar', 'Seed', seed+1);
    frameSeqSurround(sFrames(highInd):eFrames(highInd)) = noiseStream.randn(1,length(sFrames(highInd):eFrames(highInd)));
    if strcmp(noiseClass, 'binary-gaussian') || strcmp(noiseClass, 'binary')
        frameSeqSurround(frameSeqSurround > 0) = 1;
        frameSeqSurround(frameSeqSurround < 0) = -1;
    else
        frameSeqSurround = 0.3*frameSeqSurround;
    end
    frameSeqSurround = max(contrasts)*frameSeqSurround;
    % Convert to LED contrast.
    frameSeqSurround = bkg*frameSeqSurround + bkg;
else
    for k = 1 : length(sFrames)
        if strcmp(noiseClass, 'binary-gaussian')
            if contrasts(min(k,length(contrasts))) == max(contrasts) && ~isequal(contrasts,contrasts(1)*ones(size(contrasts)))
                frameSeq(sFrames(k):eFrames(k)) = contrasts(min(k,length(contrasts)))*...
                    (2*(frameSeq(sFrames(k):eFrames(k)) > 0)-1);
            else
                frameSeq(sFrames(k):eFrames(k)) = contrasts(min(k,length(contrasts)))*...
                    frameSeq(sFrames(k):eFrames(k));
            end
        else
            frameSeq(sFrames(k):eFrames(k)) = contrasts(min(k,length(contrasts)))*...
                frameSeq(sFrames(k):eFrames(k));
        end
    end

    if strcmp(stimulusClass, 'center-full') || strcmp(stimulusClass, 'center-surround')
        frameSeqSurround = ones(size(frameSeq))*bkg;
        frameSeqSurround(sFrames(2):eFrames(2)) = frameSeq(sFrames(2):eFrames(2));
        if strcmp(stimulusClass, 'center-surround')
            frameSeq(sFrames(2):eFrames(2)) = bkg;
        end
    end
end

frameSeq(frameSeq < -1) = -1;
frameSeq(frameSeq > 1) = 1;