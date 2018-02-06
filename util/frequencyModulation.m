function [F, phase, cycles] = frequencyModulation(data, sampleRate, temporalFrequency, allOrAvg, whichFreqs, discardCycles)
% frequencyModulation.m
% [F, phase, cycles] = frequencyModulation(data, sampleRate, temporalFrequency, allOrAvg, whichFreqs, discardCycles)
%
% INPUTS:
%
%
% OUTPUTS:

if ~exist('allOrAvg', 'var')
    allOrAvg = 'avg';
end

if ~exist('whichFreqs', 'var')
    whichFreqs = 1:2;
end

if ~exist('discardCycles', 'var')
    discardCycles = [];
end

allOrAvg = lower(allOrAvg);

% Calculate the cycle length.
cycleLength = sampleRate / temporalFrequency;

% Calculate the number of cycles.
numCycles = floor(length(data) / cycleLength);

switch allOrAvg
    case {'avg', 'average'}
        [F, phase, cycles] = getAvgCycleData(data, numCycles, cycleLength, whichFreqs, discardCycles);
    otherwise
        [F, phase, cycles] = getAllCycleData(data, numCycles, cycleLength, whichFreqs, discardCycles);
end
end



function [F, phase, avgCycle] = getAvgCycleData(data, numCycles, cycleLength, whichFreqs, discardCycles)
    % Get the data from each of the cycles.
    cycles = zeros(numCycles, floor(cycleLength));
    for j = 1 : numCycles
        index = round(((j-1)*cycleLength + (1 : floor(cycleLength))));
        cycles(j,:) =  data(index);
    end
    
    discardCycles(discardCycles > j) = [];
    if ~isempty(discardCycles)
        cycles(discardCycles,:) = [];
    end

    % Get the average cycle.
    avgCycle = mean(cycles, 1);

    % Do the FFT.
    ft = fft(avgCycle);

    % Pull out the F1/F2 amplitudes.
    F = abs(ft(whichFreqs+1))/length(ft)*2;

    % Get the phase.
    phase = angle(ft(whichFreqs+1));
end

function [F, phase, cycles] = getAllCycleData(data, numCycles, cycleLength, whichFreqs, discardCycles)
    % Get the data from each of the cycles.
    cycles = zeros(numCycles, floor(cycleLength));
    F = zeros(numCycles, length(whichFreqs));
    phase = zeros(numCycles, length(whichFreqs));
    
    for j = 1 : numCycles
        index = round(((j-1)*cycleLength + (1 : floor(cycleLength))));
        cycles(j,:) =  data(index);
        
        % Do the FFT.
        ft = fft(cycles(j,:));
        % Get the modulation amplitude.
        F(j,:) = abs(ft(whichFreqs+1))/length(ft)*2;
        % Get the phases in radians.
        phase(j,:) = angle(ft(whichFreqs+1));
    end
    
    discardCycles(discardCycles > j) = [];
    if ~isempty(discardCycles)
        cycles(discardCycles,:) = [];
        F(discardCycles,:) = [];
        phase(discardCycles,:) = [];
    end
end