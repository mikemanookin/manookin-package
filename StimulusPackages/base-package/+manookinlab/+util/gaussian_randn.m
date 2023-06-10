function y = gaussian_randn(varargin)
% Uses the inverse transform to generate a Gaussian distribution of random numbers.
% This method makes it possible to reproduce the same noise sequence in Matlab and Python/Numpy.
y = rand(varargin{:});
y = sqrt(2) * erfinv(2 * y - 1);
