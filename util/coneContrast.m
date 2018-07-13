function ct = coneContrast(quantalCatch, gunWeights, contrastType)

iMean = sum(quantalCatch)*0.5;
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

