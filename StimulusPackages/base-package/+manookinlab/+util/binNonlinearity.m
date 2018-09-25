function [xBin, yBin] = binNonlinearity(P, R, nonlinearityBins, method)
% Sort the data; xaxis = prediction; yaxis = response;

if ~exist('method','var')
    method = 'descend';
end

if strcmpi(method, 'histogram')
    [~, ~, idx] = histcounts(P(:),nonlinearityBins);
%     xBin = accumarray(idx(:),P(:),[],@median)';
%     yBin = accumarray(idx(:),R(:),[],@median)';
    xBin = accumarray(idx(:),P(:),[],@mean)';
    yBin = accumarray(idx(:),R(:),[],@mean)';
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
    [xBin, yBin] = binNonlinearity_Count(P, R, nonlinearityBins, method);
    
    % Make sure you don't get a lot of replicate values at zero.
    if length(unique(xBin)) < length(xBin)
        % Remove replicate bin points on the x-axis.
        % Unique values
        [~,idxu,idxc] = unique(xBin);
        % count unique values (use histc in <=R2014b)
        [count, ~, idxcount] = histcounts(idxc,numel(idxu));
        % Where is greater than one occurence
        repIndex = find(count(idxcount)>1);
        % Get the value to remove.
        remval = xBin(repIndex(1));
        % Copy R and P and do it again without the value giving trouble.
        R(P == remval) = [];
        P(P == remval) = [];
        [xBin, yBin] = binNonlinearity_Count(P, R, nonlinearityBins, method);
    end
end

% if length(unique(xBin)) < length(xBin)
%     % Remove replicate bin points on the x-axis.
%     % Unique values
%     [~,idxu,idxc] = unique(xBin);
%     % count unique values (use histc in <=R2014b)
%     [count, ~, idxcount] = histcounts(idxc,numel(idxu));
%     % Where is greater than one occurence
%     repIndex = find(count(idxcount)>1);
%     yBin(repIndex(1)) = median(yBin(repIndex));
%     % Remove the duplicates.
%     xBin(repIndex(2:end)) = [];
%     yBin(repIndex(2:end)) = [];
% end
end

function [xBin, yBin] = binNonlinearity_Count(P, R, nonlinearityBins, method)
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
