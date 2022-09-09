function qCatch = computeQuantalCatch(wavelength, energySpectrum)

cDensity = 0.35; % Cone optical density.
rDensity = 0.17; % Rod optical density.
coneArea = 0.6; %0.37; % Cone cross-sectional area (um^2)
rodArea = 1.7; % Rod cross-sectional area (um^2)

% Do quantal correction.
h = 6.626e-34; % Joules/sec
c = 3.0e8; % meters/sec

% Convert wavelength from nm to meters.
lambda = wavelength * 1e-9;

quantalSpectrum = (energySpectrum(:) .* lambda(:)) / (h*c);

% Compute the Quantal catch.
p = manookinlab.util.PhotoreceptorSpectrum( wavelength, [559 530 430 493],[cDensity*ones(1,3) rDensity]);
p = p / sum(p(1, :));
qCatch = p * quantalSpectrum(:);

qCatch(1:3) = qCatch(1:3) * coneArea;
qCatch(4) = qCatch(4) * rodArea;

