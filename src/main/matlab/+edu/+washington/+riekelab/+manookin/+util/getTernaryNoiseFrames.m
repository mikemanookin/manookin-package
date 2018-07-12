function frameSequence = getTernaryNoiseFrames(varargin)
% frameSequence = getTernaryNoiseFrames(varargin)
%
% INPUTS:
%   noiseClass: 'binary' or 'gaussian'
%   numXChecks
%   numYChecks
%   numStimFrames
%   seed
%   dx
%   dy
%   dt
%
% OUTPUT:
%   frameSequence: (x,y,t) sequence of frames

ip = inputParser();
ip.addParameter('noiseClass', 'binary', @(x)ischar(x));
ip.addParameter('numXChecks', 10, @(x)isfloat(x) || @(x)isinteger(x));
ip.addParameter('numYChecks', 1, @(x)isfloat(x) || @(x)isinteger(x));
ip.addParameter('numStimFrames', 60, @(x)isfloat(x) || @(x)isinteger(x));
ip.addParameter('seed', 1, @(x)isfloat(x) || @(x)isinteger(x));
ip.addParameter('dx', 1, @(x)isfloat(x) || @(x)isinteger(x));
ip.addParameter('dy', 0, @(x)isfloat(x) || @(x)isinteger(x));
ip.addParameter('dt', 1, @(x)isfloat(x) || @(x)isinteger(x));
ip.parse(varargin{:});

% Pull the inputs.
noiseClass = ip.Results.noiseClass;
numYChecks = ip.Results.numYChecks;
numXChecks = ip.Results.numXChecks;
numStimFrames = ip.Results.numStimFrames;
dx = ip.Results.dx;
dy = ip.Results.dy;
dt = ip.Results.dt;
seed = ip.Results.seed;


% Seed the random number generator.
noiseStream = RandStream('mt19937ar', 'Seed', seed);

% Create the frame sequence.
if numXChecks == 0 || numYChecks == 0
    if strcmp(noiseClass, 'binary')
        eta = double(noiseStream.randn(max(numYChecks, numXChecks), numStimFrames) > 0)*2 - 1;
    else
        eta = 0.3*noiseStream.randn(max(numYChecks, numXChecks), numStimFrames);
    end

    % Generate the frame sequence.
    frameSequence = (eta + circshift(eta, [max(dy, dx), dt])) / 2;
else
    if strcmp(noiseClass, 'binary')
        eta = double(noiseStream.randn(numYChecks, numXChecks, numStimFrames) > 0)*2 - 1;
    else
        eta = 0.3*noiseStream.randn(numYChecks, numXChecks, numStimFrames);
    end

    % Generate the frame sequence.
    frameSequence = (eta + circshift(eta, [dy, dx, dt])) / 2;
end


