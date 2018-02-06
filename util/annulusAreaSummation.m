function r = annulusAreaSummation(params, radii)

% The last radius is the outer radius.
outerRadius = radii(end);

% Get the outer radius response.
o = abs(params(1).*(1 - exp(-(outerRadius.^2)./params(2))) - params(3).*(1 - exp(-(outerRadius.^2)./params(4))));

r = abs(params(1).*(1 - exp(-(radii(1:end-1).^2)./params(2))) - params(3).*(1 - exp(-(radii(1:end-1).^2)./params(4))));

% Subtract the outer radius response from the inner radius mask.
r = abs(o - r);

