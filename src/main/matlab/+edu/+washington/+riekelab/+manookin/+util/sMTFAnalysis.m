function result = sMTFAnalysis(groupData, binRate, analysisType, allOrAvg, discardCycles)


if nargin == 1
    binRate = 60;
    analysisType = 'spikes';
    allOrAvg = 'avg';
    discardCycles = [];
elseif nargin == 2
    analysisType = 'spikes';
    allOrAvg = 'avg';
    discardCycles = [];
elseif nargin == 3
    allOrAvg = 'avg';
    discardCycles = [];
elseif nargin == 4
    discardCycles = [];
end


% Allocate memory to some variables.
switch allOrAvg
    case {'avg', 'average'}
        sf = zeros(1, length(groupData));
        F1 = zeros(1, length(groupData));
        ph = zeros(1, length(groupData));
    otherwise
        sf = [];
        F1 = [];
        ph = [];
end

for k = 1 : length(groupData)
    data = groupData(k).data;

    if isfield(groupData(k).params, 'stimStart')
        stimStart = groupData(k).params.stimStart;
    else
        stimStart = groupData(k).params.preTime * groupData(k).params.sampleRate + 1;
    end

    if isfield(groupData(k).params, 'stimEnd')
        stimEnd = groupData(k).params.stimEnd;
    else
        stimEnd = (groupData(k).params.preTime + groupData(k).params.stimTime) * groupData(k).params.sampleRate;
    end

    % Bin the data according to type.
    switch analysisType
        case 'spikes'
            bData = BinSpikeRate(data(stimStart:stimEnd), binRate, groupData(k).params.sampleRate);
        otherwise
            bData = binData(data(stimStart:stimEnd), binRate, groupData(k).params.sampleRate);
    end
    
    [F, phase] = frequencyModulation(bData, ...
        binRate, groupData(k).params.temporalFrequency, allOrAvg, 1, discardCycles);
    
    switch allOrAvg
        case {'avg', 'average'}
            sf(k) = groupData(k).params.spatialFrequency; 
            F1(k) = F;
            ph(k) = phase;
        otherwise
            sf = [sf groupData(k).params.spatialFrequency*ones(1,length(F))]; 
            F1 = [F1 F(:)'];
            ph = [ph phase(:)'];
    end
    
    
end

% Get the unique contrasts.
uniqueSF = unique(sf);

avgF1 = zeros(1, length(uniqueSF));
semF1 = zeros(1, length(uniqueSF));
avgPh = zeros(1, length(uniqueSF));
for k = 1 : length(uniqueSF)
    index = (sf == uniqueSF(k));
    avgF1(k) = mean(F1(index));
    avgPh(k) = mean(ph(index));
    
    if ~strcmpi(allOrAvg, 'avg') && ~strcmpi(allOrAvg, 'average')
        semF1(k) = sem(F1(index));
    end
end

result = struct();
result.uniqueSF = uniqueSF;
result.avgF1 = avgF1;
result.semF1 = semF1;
result.avgPh = avgPh;