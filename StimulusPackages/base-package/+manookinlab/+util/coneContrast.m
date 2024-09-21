function ct = coneContrast(quantalCatch, gunWeights, contrastType)

if nargin < 3
    contrastType = 'weber';
end

iMean = sum(quantalCatch);
iDelta = sum((gunWeights(:)*ones(1,4)).*quantalCatch);
iMax = iMean + iDelta;
iMin = iMean - iDelta;

if strcmpi(contrastType, 'weber')
    % Calculate the Weber contrast.
    ct = (iMax - iMean) ./ iMean;
else
    % Calculate the Michaelson contrast.
    ct = (iMax - iMin) ./ (iMax + iMin);
end

