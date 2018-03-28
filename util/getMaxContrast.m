function [m, ct, deltaRGB] = getMaxContrast(q, isoType, coneRatio)
% 
% q : [m x n] matrix of quantal catch values where columns are L, M, S
% catch and rows are R G B.
%
% isoType : isolation type options are 'L-iso', 'M-iso', 'S-iso', 'LM-iso',
% 'red-green isoluminant', and 'red-green isochromatic'
% q = qCatch.ndf00([1,2,4],1:3);

% For isoluminant stimuli. L:M is 2:1 for Northern Europeans and 1:1 for
% macaque.
if ~exist('coneRatio','var')
    coneRatio = [1 1]; %[2 1];
end

switch isoType
    case 'L-iso'
        isoM = [1 0 0]';
        lockIndex = 1;
    case 'M-iso'
        isoM = [0 1 0]';
        lockIndex = 2;
    case 'S-iso'
        isoM = [0 0 1]';
        lockIndex = 3;
    case 'LM-iso'
        isoM = [1 1 0]';
        lockIndex = 2; % This gets L and M ct closest.
    case 'red-green isoluminant'
%         m = getRGIsoluminantMeans();
%         m = m(:)';
%         % Define the delta RGB.
%         deltaRGB = [1 -1 0];
%         % Calculate the cone contrast.
%         ct = getConeContrasts(m);
%         return;
    case 'red-green isochromatic'
        m = getRGIsochromaticMeans();
        m = m(:)';
        % Define the delta RGB.
        deltaRGB = [1 1 0];
        % Calculate the cone contrast.
        ct = getConeContrasts(m);
        return;
    otherwise
        disp('Error: Please select a valid stimulus type.');
        return
end

% Set minimization options.
options = optimoptions('fmincon',...
    'Display','off',...
    'MaxFunctionEvaluations',6000,...
    'MaxIterations',3000);

if strcmp(isoType, 'red-green isoluminant')    
    v = fmincon(@errRGIsoluminance,0.25,[],[],[],[],0.01,0.5,[],options);
    deltaRGB = getRGIsoLumDelta([0.5;v],[coneRatio(1) -coneRatio(2)]);
    deltaRGB(3) = 0;
    m = [0.5 v 0];
elseif strcmp(isoType, 'red-green isochromatic')    
    v = fmincon(@errRGIsochromatic,0.22,[],[],[],[],0.01,0.5,[],options);
    deltaRGB = getRGIsoLumDelta([v;0.5],[coneRatio(1) coneRatio(2)]);
    deltaRGB(3) = 0;
    m = [0.5 v 0];
else
    initialGuess = [0.2 0.2];
    % Mean cannnot go below 0 or above 0.5. Define upper and lower bounds.
    lb = zeros(1,2); 
    ub = 0.5*ones(1,2);
    % Use constrained minimization.
    v = fmincon(@maxCtErrFun,initialGuess,[],[],[],[],lb,ub,[],options);

    switch lockIndex
        case 1
            m = [0.5 v];
        case 2
            m = [v(1) 0.5 v(2)];
        case 3
            m = [v 0.5];
    end

    % Get the delta values for each LED.
    deltaRGB = getDeltaRGB(m);
end
% Calculate the final cone contrasts (L,M,S).
ct = getConeContrasts(m);

%--------------------------------------------------------------------------
% Nested utility functions
    function err = maxCtErrFun(gunMeans)
        if lockIndex == 1
            gTmp = [0.5 gunMeans(1:2)];
        elseif lockIndex == 2
            gTmp = [gunMeans(1) 0.5 gunMeans(2)];
        else
            gTmp = [gunMeans(1:2) 0.5];
        end
        gunMeans = gTmp;

        deltaRGB = getDeltaRGB(gunMeans);

        % Calculate the mean photon flux.
        meanFlux = (gunMeans(:)*ones(1,3)).*q(:,1:3);

        iDelta = sum((deltaRGB(:)*ones(1,3)).*meanFlux);
        % Calculate the max contrast of each cone type. (Weber contrast)
        cWeber = iDelta ./ sum(meanFlux,1);

        if strcmp(isoType, 'LM')
            err = min((1 - cWeber(1:2)).^2);
        else
            err = (1 - cWeber(lockIndex)).^2;
        end

        % % Michaelson.
        % iMax = iDelta + sum(meanFlux,1);
        % iMin = sum(meanFlux) - iDelta;
        % cMichaelson = (iMax-iMin)./(iMax+iMin);
    end

    function deltaRGB = getDeltaRGB(gunMeans)
        deltaRGB = 2*(q(:,1:3).*(ones(3,1)*gunMeans(:)')')' \ isoM;
        deltaRGB = deltaRGB / max(abs(deltaRGB));
    end

    function cWeber = getConeContrasts(gunMeans)
        meanFlux = (gunMeans(:)*ones(1,3)).*q(:,1:3);

        iDelta = sum((deltaRGB(:)*ones(1,3)).*meanFlux);
        % Calculate the max contrast of each cone type. (Weber contrast)
        cWeber = iDelta ./ sum(meanFlux,1);
    end

    % Calculate the parameters for red-green isoluminance.
    function err = errRGIsoluminance(greenMean)
        lmRatio = coneRatio;
        meanFlux = ([0.5;greenMean]*ones(1,2)).*q(1:2,1:2); % sum(([0.5;greenMean]*ones(1,2)).*q(1:2,1:2));
        deltaRGB = getRGIsoLumDelta([0.5;greenMean],[lmRatio(1) -lmRatio(2)]);
        iDelta = sum((deltaRGB(:)*ones(1,2)).*meanFlux);
        % Calculate the max contrast of each cone type. (Weber contrast)
        cWeber = iDelta ./ sum(meanFlux,1);
        
        err = max((1 - [cWeber(1) -cWeber(2)]).^2);
    end
    
    % Calculate the parameters for red-green isochromatic.
    function err = errRGIsochromatic(greenMean)
        meanFlux = ([greenMean;0.5]*ones(1,2)).*q(1:2,1:2);
        deltaRGB = getRGIsoLumDelta([greenMean;0.5],coneRatio);
        iDelta = sum((deltaRGB(:)*ones(1,2)).*meanFlux);
        % Calculate the max contrast of each cone type. (Weber contrast)
        cWeber = iDelta ./ sum(meanFlux,1);
        
        err = max((1 - cWeber).^2);
    end

    % Calculate the parameters for the red-green isochromatic stimulus.
    function gunMeans = getRGIsochromaticMeans()
        % Calculate the RG means.
        gunMeans = q(1:2,1:2)' \ [1; 0.7613];
        gunMeans = gunMeans/max(abs(gunMeans));
        gunMeans = gunMeans*0.5;
        gunMeans(3) = 0; % Set the blue to zero.
        gunMeans = max(gunMeans,0); 
    end

    function gunMeans = getRGIsoluminantMeans()
        % Calculate the RG means.
        gunMeans = q(1:2,1:2)' \ [0.862; 1];
        gunMeans = gunMeans/max(abs(gunMeans));
        gunMeans = gunMeans*0.5;
        gunMeans(3) = 0; % Set the blue to zero.
        gunMeans = max(gunMeans,0); 
    end

    % Calculate the delta RG values at red-green isoluminance.
    function deltaRGB = getRGIsoLumDelta(gunMeans, lmRatio)
        % 2-to-1 L:M ratio
%         deltaRGB = 2*(q(1:2,1:2).*(ones(2,1)*gunMeans(:)')')' \ lmRatio(:);
%         deltaRGB = deltaRGB/max(abs(deltaRGB));
        
        deltaRGB = fmincon(@getIsoContrastErr,lmRatio,[],[],[],[],-1*ones(2,1),1*ones(2,1),[],options);
        deltaRGB = deltaRGB/max(abs(deltaRGB));
        
        % Calculate the isoluminant/isochromatic contrast.
        function err = getIsoContrastErr(dRG)
            meanFlux = (gunMeans(:)*ones(1,2)).*q(1:2,1:2);
            iDelta = sum((dRG(:)*ones(1,2)).*meanFlux);
            % Calculate the max contrast of each cone type. (Weber contrast)
            cWeber = iDelta ./ sum(meanFlux,1);
            err = (coneRatio(2)*cWeber(1)+coneRatio(1)*cWeber(2)).^2;
        end
    end
end




