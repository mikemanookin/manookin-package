function [xBin, yBin] = binNonlinearity(P, R, nonlinearityBins, method)
% Sort the data; xaxis = prediction; yaxis = response;

if ~exist('method','var')
    method = 'descend';
end

if strcmpi(method, 'histogram')
    [~, ~, idx] = histcounts(P(:),nonlinearityBins);
    xBin = accumarray(idx(:),P(:),[],@median);
    yBin = accumarray(idx(:),R(:),[],@median);
    plot(xBin,yBin,'.');
elseif strcmpi(method, 'spacing')
    bsize = numel(P)/nonlinearityBins;
    x = P(:);
    y = R(:);
    [x,index] = sort(x);
    y = y(index);
    xBin = zeros(1,nonlinearityBins);
    yBin = zeros(1,nonlinearityBins);
    for n = 1 : nonlinearityBins
        sIndex = round((n-1)*bsize) + 1;
        if n < nonlinearityBins
            eIndex = round(n*bsize);
        else
            eIndex = length(x);
        end
        xBin(n) = mean(x(sIndex:eIndex));
        yBin(n) = mean(y(sIndex:eIndex));
    end
else
    if strcmpi(method,'descend')
        [a, b] = sort(P(:),'descend');
    else
        [a, b] = sort(P(:),'ascend');
    end
    xSort = a;
    ySort = R(b);

    % Bin the data.
    valsPerBin = floor(length(xSort) / nonlinearityBins);
    xBin = mean(reshape(xSort(1 : nonlinearityBins*valsPerBin),valsPerBin,nonlinearityBins));
    yBin = mean(reshape(ySort(1 : nonlinearityBins*valsPerBin),valsPerBin,nonlinearityBins));
end