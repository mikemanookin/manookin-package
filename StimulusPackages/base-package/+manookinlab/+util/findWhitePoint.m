function err = findWhitePoint(params, q)

% Make sure you have non-negative parameters.
params(params < 0) = 0;

% Target cone ratio.
t = [1, 0.877, 0.329];

r = sum( (params(:)*ones(1,3)) .* q);
r = r / r(1);

% Calculate the mean-squared error.
err = mean((t(1:2) - r(1:2)).^2);

% params = [1 4 0];
% r = sum( (params(:)*ones(1,3)) .* q);
% r = r / r(1)