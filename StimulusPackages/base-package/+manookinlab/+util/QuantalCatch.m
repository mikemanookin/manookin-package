function qCatch = QuantalCatch(receptorSpectra, quantalSpectra)

% Calculate the activation of each receptor class by each gun
gunsToReceptors = quantalSpectra' * receptorSpectra;

% Calculate the quantal catch in R*/sec.
if size(gunsToReceptors,1) > 3
    qCatch(1:3,:) = gunsToReceptors(1:3,:) * 0.67 * 0.37; % The cone catches.
    qCatch(4,:) = gunsToReceptors(4,:) * 0.67 * 1.7; % The rod catch.
else 
    % The cone catch.
    qCatch = gunsToReceptors * 0.67 * 0.37;
end


