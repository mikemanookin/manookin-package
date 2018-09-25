function [m, ct] = maxConeContrast(Q, stimulusMatrix)
% Determine the RGB background means that would maximize cone-iso contrast
% for a specific cone type.
% [m, ct] = maxConeContrast(Q, stimulusMatrix)
%
% Inputs: 
%   Q: Quantal catch matrix.
%   stimulusMatrix: Desired cone modulation [L M S]; for example, S-cone
%   isolation would be [0 0 1].
%
% Outputs:
%   m: RGB background means.
%   ct: The maximum cone contrast at the background means (m).


    ledMeans = 0.5*ones(1,3); % The starting means
    
    lb = zeros(1,3); % Lower bound on means
    ub = ones(1,3); % Upper bound on means
    m = fmincon(@maxCt, ledMeans,[],[],[],[],lb,ub); % Find the minimum.
    
    ct = 1 - maxCt(m); % Get the max contrast.

    function ct = maxCt(ledMeans)
        deltaRGB = (Q(:,1:3).*(ones(3,1)*ledMeans)')' \ stimulusMatrix(:);
        deltaRGB = deltaRGB / max(abs(deltaRGB));
        ct = deltaRGB' * Q(:,1:3) .* ledMeans ./ (ledMeans .* sum(Q(:,1:3)));
        if sum(ct(stimulusMatrix==0)) > 0.04
            ct = 1;
        else
            ct = 1 - min(ct(stimulusMatrix==1));
        end
    end

end