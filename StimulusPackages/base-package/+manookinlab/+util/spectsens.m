function [withOD, extinction] = spectsens(LambdaMax, OpticalDensity, Output, StartWavelength, EndWavelength, Res)
%spectsens returns a photopigment spectral sensitivity curve
%as defined by Carroll, McMahon, Neitz, and Neitz.
%[withOD, extinction curve] = spectsens(LambdaMax, OpticalDensity, OutputType, StartWavelength, EndWavelength,
%Resolution)
%
%LambdaMax = Wavelength peak for photopigment (default = 559)
%OpticalDensity = optical density required (default = 0.20)
%OutputType = log or anti-log.  if log, maximum data ouput is 0.  if
%anti-log, data output is between 0 and 1 (default = log).
%StartWavelength = beginning wavelength (default = 380)
%EndWavelength = end wavelength (default = 780)
%Resolution = Number of data points (default = 1000)


format long;

if nargin < 6, Res = 1000; end
if nargin < 5, EndWavelength = 780; end
if nargin < 4, StartWavelength = 380; end
if nargin < 3, Output = 'log'; end
if nargin < 2, OpticalDensity = 0.2000; end
if nargin < 1, LambdaMax = 559; end

A = 0.417050601;
B = 0.002072146;
C = 0.000163888;
D = -1.922880605;
E = -16.05774461;
F = 0.001575426;
G = 5.11376E-05;
H = 0.00157981;
I = 6.58428E-05;
J = 6.68402E-05;
K = 0.002310442;
L = 7.31313E-05;
M = 1.86269E-05;
N = 0.002008124;
O = 5.40717E-05;
P = 5.14736E-06;
Q = 0.001455413;
R = 4.217640000E-05;
S = 4.800000000E-06;
T = 0.001809022;
U = 3.86677000E-05;
V = 2.99000000E-05;
W = 0.001757315;
X = 1.47344000E-05;
Y = 1.51000000E-05;
Z = OpticalDensity+0.00000001;

if (EndWavelength-StartWavelength)==0
    inc = 1/Res;
else
    inc = ((EndWavelength - StartWavelength)/Res);
end
A2=(log10(1.00000000/LambdaMax)-log10(1/558.5));
vector = log10((StartWavelength:inc:EndWavelength).^-1);
const = 1/sqrt(2*pi);

exTemp=log10(-E+E*tanh(-(((10.^(vector-A2)))-F)/G))+D+A*tanh(-(((10.^(vector-A2)))-B)/C) - (J/I*(const*exp(1).^(-0.5*(((10.^(vector-A2))-H)/I).^2))) - (M/L*(const*exp(1).^(-0.5*(((10.^(vector-A2))-K)/L).^2))) - (P/O*(const*exp(1).^(-0.5*(((10.^(vector-A2))-N)/O).^2))) + (S/R*(const*exp(1).^(-0.5*(((10.^(vector-A2))-Q)/R).^2))) + ((V/U*(const*exp(1).^(-0.5*(((10.^(vector-A2))-T)/U).^2)))/10) + ((Y/X*(const*exp(1).^(-0.5*(((10.^(vector-A2))-W)/X).^2)))/100);
ODTemp = log10((1-10.^-((10.^exTemp)*Z))/(1-10^-Z));

if (strcmp(Output, 'log') == 1)
    extinction = exTemp;
    withOD = ODTemp;
else
    extinction = 10.^(exTemp);
    withOD = 10.^(ODTemp);
end
