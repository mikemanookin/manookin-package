function quantalCatch = computePhotoreceptorCatch(paths, spectrum, varargin)

p = inputParser;
addParameter(p, 'species', 'macaque', @(x)ischar(x));
parse(p, varargin{:});

species = p.Results.species;

switch species
    case 'marmoset'
        photoreceptorPeaks = [563, 543, 423, 493];
    case 'mouse'
        photoreceptorPeaks = [508, 508, 360, 498];
    otherwise
        photoreceptorPeaks = [559, 530, 430, 493];
end


h = 6.62607015e-34; % Planck's constant in Joules/sec
c = 2.99792458e8; % Speed of light in meters/sec
rDensity = 0.35; % Cone optical density.
cDensity = 0.17; % Rod optical density.
coneArea = 0.6; %0.6; %0.37; % Cone cross-sectional area (um^2)
rodArea = 1.7; % Rod cross-sectional area (um^2)
led_names = {'red','green','blue'};
quantalCatch = zeros(length(led_names),4);

try
    canComputeCatch = true;
    m = containers.Map();
    settings = paths.keys;
    for k = 1:numel(settings)
        setting = settings{k};
        if exist(paths(setting), 'file')
            t = readtable(paths(setting), 'Format', '%s %s %f %f %f %f %s');
            t.date = datetime(t.date);
            t = sortrows(t, 'date', 'descend');
            m(setting) = t;
        else
            disp('Warning: Flux factors not calibrated, cannot compute quantal catch.');
            canComputeCatch = false;
        end
    end
    if canComputeCatch
        for ii = 1 : length(led_names)
            flashArea = (m(led_names{ii}).diameter(1)/2)^2 * pi;
            ledPower = m(led_names{ii}).power(1) * 1e-9;
            spect = spectrum(led_names{ii});
            wavelength = spect(:,1);
            energySpectrum = spect(:,2) / sum(spect(:,2));
            lambda = wavelength * 1e-9;

            quantalSpectrum = (energySpectrum * ledPower) .* lambda / (h*c);

            % Compute the Quantal catch.
            p = manookinlab.util.PhotoreceptorSpectrum( wavelength, photoreceptorPeaks,[cDensity*ones(1,3) rDensity]);
            photonFlux = quantalSpectrum' * p';
            fluxPerSqMicron = photonFlux / flashArea;
            qCatch = fluxPerSqMicron;

            qCatch(1:3) = qCatch(1:3) * coneArea;
            qCatch(4) = qCatch(4) * rodArea;
            quantalCatch(ii,:) = qCatch(:)';
        end
    end
catch ME
    disp(['Error: ',ME.message]);
end