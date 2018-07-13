function [M, circlePoints] = generateTextureCircle(S, sigma, C, seed)
%C is contrast

% Default seed is 1.
if ~exist('seed','var')
    seed = 1;
end

% Seed the number generator.
noiseStream = RandStream('mt19937ar', 'Seed', seed);

winL = 200;
M = noiseStream.rand(S);
if sigma>0
    win = fspecial('gaussian',winL,sigma);
    win = win ./ sum(win(:));
    M = imfilter(M,win,'replicate');
    M = M./max(M(:));
end

[M, circlePoints] = makeUniformDistCircle(M,C);
