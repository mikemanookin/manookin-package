function receptorSpectra = PhotoreceptorSpectrum(wavelength, lambdaMax, OD)

if ~exist('wavelength','var')
    wavelength = 370:780;
end
if ~exist('lambdaMax','var')
    lambdaMax = [559 530 430 493]; % Default values for macaque (LMSR).
    % Baylor et al 1987 fit: 561 531 430
end
if ~exist('OD','var')
    if length(lambdaMax) == 4
        OD = [0.35*ones(1,3) 0.35];
    else
        OD = 0.35*ones(size(lambdaMax));
    end
end

receptorSpectra = zeros(length(lambdaMax), length(wavelength)); 
for a = 1 : length(lambdaMax)
    receptorSpectra(a,:) = manookinlab.util.spectsens(lambdaMax(a), OD(a), 'alog', wavelength(1), wavelength(end), length(wavelength)-1);
end

% constants = [
%     0.417050600981105; %A
%     0.00207214609903167; %B
%     0.000163887833315205;
%     -1.92288060457733; 
%     -16.0577446068655; % E
%     0.00157542568514221; % F
%     0.0000511375520964685; %G
%     0.00157980963962036; %H
%     0.0000658427524201436; %I
%     0.0000668401522059188; %J
%     0.00231044180724843; %K
%     0.0000731313176638167; %L
%     0.0000186268540365115; %M
%     0.00200812408050576; %N
%     0.0000540717445074862; %O
%     5.14735555961554e-06; %P
%     0.00145541288156983; %Q
%     0.0000421763515240877; %R
%     4.80304781255631e-06; %S
%     0.0018090223920758; %T
%     0.000038667667342666; %U
%     0.0000298963553165856; %V
%     0.00175731492164485; %W
%     0.0000147343775055144; %X
%     0.00001511265490002; %Y
%     ];
% 
% receptorSpectra = zeros(length(lambdaMax), length(wavelength));
% for j = 1:length(lambdaMax)
%     tmp = log10(1./lambdaMax(j)) - log10(1./558.5);
% 
%     extinction = log10(-constants(5)+constants(5) .* tanh(-(((10.^(log10(1./(wavelength))-(tmp))))-constants(6))./constants(7)))...
%         + constants(4)+constants(1).*tanh(-(((10.^(log10(1./(wavelength))-(tmp))))-constants(2))./constants(3))...
%         - (constants(10)./constants(9).*((1./(sqrt(2.*pi()))).*exp(1).^((-1./2).*(((10.^(log10(1./wavelength)-(tmp)))-constants(8))./constants(9)).^2)))...
%         - (constants(13)./constants(12).*((1./(sqrt(2.*pi()))).*exp(1).^((-1./2).*(((10.^(log10(1./wavelength)-(tmp)))-constants(11))./constants(12)).^2)))...
%         - (constants(16)./constants(15).*((1./(sqrt(2.*pi()))).*exp(1).^((-1./2).*(((10.^(log10(1./wavelength)-(tmp)))-constants(14))./constants(15)).^2)))...
%         + (constants(19)./constants(18).*((1./(sqrt(2.*pi()))).*exp(1).^((-1./2).*(((10.^(log10(1./wavelength)-(tmp)))-constants(17))./constants(18)).^2)))...
%         + ((constants(22)./constants(21).*((1./(sqrt(2.*pi()))).*exp(1).^((-1./2).*(((10.^(log10(1./wavelength)-(tmp)))-constants(20))./constants(21)).^2)))./10)...
%         + ((constants(25)./constants(24).*((1./(sqrt(2.*pi()))).*exp(1).^((-1./2).*(((10.^(log10(1./wavelength)-(tmp)))-constants(23))./constants(24)).^2)))./100);
% 
%     withOD = log10((1-10.^-((10.^(extinction)).*(OD(j)*1e-8)))./(1-10.^-(OD(j)*1e-8)));
% 
%     receptorSpectra(j,:) = 10.^withOD;
% end

