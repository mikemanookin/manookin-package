function R = spotSMTFAnalysis(group, dataType)

if ~exist('dataType', 'var')
    dataType = 'spikes';
end

deviceName = 'Amplifier_Ch1';

R = struct();

radii = zeros(1, length(group.epochs));
for k = 1 : length(group.epochs)
    for m = 1 : length(group.epochSignals(k).signals)
        if strcmp(group.epochSignals(k).signals(m).deviceName, deviceName)
            sampleRate = group.epochSignals(k).signals(m).sampleRate;
            radii(k) = group.epochSignals(k).protocolParameters('radius');
            stimulusClass{k} = group.epochSignals(k).protocolParameters('stimulusClass'); %#ok<AGROW>
            temporalClass = group.epochSignals(k).protocolParameters('temporalClass');
            temporalFrequency = group.epochSignals(k).protocolParameters('temporalFrequency');
            preTime = group.epochSignals(k).protocolParameters('preTime');
            stimTime = group.epochSignals(k).protocolParameters('stimTime');
            if strcmp(dataType, 'spikes')
                data = group.epochSignals(k).signals(m).spikes * sampleRate;
            else
                data = group.epochSignals(k).signals(m).data;
                prePts = round(preTime*1e-3*sampleRate);
                if prePts > 0
                    data = data - median(data(1:prePts));
                else
                    data = data - median(data);
                end
            end
            
            % Bin the data.
            data = binData(data(ceil(preTime*1e-3*sampleRate)+1 : end), 60, sampleRate);
            data = data(:)';
            
            if strcmpi(temporalClass, 'sinewave') || strcmpi(temporalClass, 'squarewave')
                % Determine the number of cycles.
                numCycles = floor(stimTime*1e-3*temporalFrequency);
                % The cycle width in samples.
                cycleWidth = 60 / temporalFrequency;
                
                avgCycle = zeros(1, floor(cycleWidth));
                for n = 1 : numCycles
                    index = round((n-1)*cycleWidth) + 1 : round(n*cycleWidth);
                    avgCycle = avgCycle + data(index);
                end
                avgCycle = avgCycle / n;
                
                % Take the FFT.
                ft = fft(avgCycle);
                r(k,:) = abs(ft(2 : 3))/length(ft)*2; %#ok<AGROW>
                phase(k,:) = angle(ft(2:3)); %#ok<AGROW>
            else
                r(k,:) = mean(data(1 : floor(stimTime*1e-3*sampleRate))); %#ok<AGROW>
                phase = [];
            end
            
        end
    end
end

% Find the spot and annulus indices.
spots = find(strcmp(stimulusClass,'spot'));
annuli = find(strcmp(stimulusClass,'annulus'));

if ~isempty(spots)
    sRadii = radii(spots);
    [sRadii, b] = sort(sRadii); % Sort
    sR = r(spots(b),:);
    
    R.spot.radii = sRadii;
    R.spot.response = sR;
    if ~isempty(phase)
        sPhase = phase(spots(b),:);
        R.spot.phase = sPhase;
    end
    
    yd = abs(sR(:,1)');
    params0 = [max(yd) 200 0.1*max(yd) 400];
    [Kc,sigmaC,Ks,sigmaS] = fitDoGAreaSummation(2*sRadii(:)', yd, params0);
    res = DoGAreaSummation([Kc,sigmaC,Ks,sigmaS], 2*sRadii(:)');
end

if ~isempty(annuli)
    aRadii = radii(annuli);
    [aRadii,b] = sort(aRadii); % Sort
    aR = r(annuli(b),:);
    
    R.annulus.radii = aRadii;
    R.annulus.response = aR;
    if ~isempty(phase)
        aPhase = phase(annuli(b),:);
        R.annulus.phase = aPhase;
    end
    
    yd = abs(aR(:,1)');
    params0 = [max(yd) 200 0.1*max(yd) 400];
    params = fitAnnulusAreaSum([aRadii(:)' 456], yd, params0);
    res = annulusAreaSummation(params, [aRadii(:)' 456]);
    sigmaC = params(2);
    sigmaS  = params(4);
end
