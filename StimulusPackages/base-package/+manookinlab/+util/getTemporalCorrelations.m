function [c,c2,c3] = getTemporalCorrelations(S, stimulusType)

    % Get the four centermost stixels.
    numCenterStixels = 4;
    m = size(S,1);
    vind = floor(m/2)-2 + (1:numCenterStixels);
    c = zeros(1,size(S,ndims(S)));
    for k = 1 : numCenterStixels
        c = double(squeeze(S(vind(k),1,:))>0)' * 2^(k-1) + c;
    end
    c2 = c;
    c3 = c;
    return
% 
%     if ismatrix(S)
%         N = size(S,1);
%     else
%         N = size(S,1)*size(S,2);
%     end
% 
%     c2 = zeros(1,size(S,ndims(S)));
% 
%     % Calculate the two-point correlations
%     if ismatrix(S)
%         foo = (S(1:end-1,1:end-1) .* S(2:end,2:end)) + (S(1:end-1,2:end) .* S(2:end,1:end-1));
%         c2(2:end) = sum(foo,1);
%     else
%         foo = (S(1:end-1,:,1:end-1) .* S(2:end,:,2:end)) + (S(1:end-1,:,2:end) .* S(2:end,:,1:end-1));
%         c2(2:end) = squeeze(sum(sum(foo,1),2));
%     end
% 
%     c2 = c2 / (N - 1);
%     c2(2:end) = c2(2:end) - mean(c2(2:end));
% 
%     % Calculate the three-point correlations
% %     c3 = getThreePtCorr(S, stimulusType);
%     c3 = getSTCorr(S, stimulusType);
%     c3 = c3 / (N-1);
%     c3(2:end) = c3(2:end) - mean(c3(2:end));
% 
%     if contains(stimulusType,'3-point')
%         c = getThreePtCorr(S, stimulusType);
%     else
%         c = c3;
%     end
end

function c = getThreePtCorr(S, stimulusType)
    c = zeros(size(S));
    
    % Diverging correlations
    if contains(stimulusType,'diverging')
        if ismatrix(c)
            for k = 2 : size(S,1)
                c(k,2:end) = S(k,1:end-1) .* ((S(k,2:end) + S(k-1,2:end))/2);
            end
        else
            for k = 2 : size(S,1)
                for m = 1 : size(S,2)
                    c(k,m,2:end) = S(k,m,1:end-1) .* ((S(k,m,2:end) + S(k-1,m,2:end))/2);
                end
            end
        end
    else
        if ismatrix(c)
            for k = 2 : size(S,1)
                c(k,2:end) = S(k,2:end) .* ((S(k,1:end-1) + S(k-1,1:end-1))/2);
            end
        else
            for k = 2 : size(S,1)
                for m = 1 : size(S,2)
                    c(k,m,2:end) = S(k,m,2:end) .* ((S(k,m,1:end-1) + S(k-1,m,1:end-1))/2);
                end
            end
        end
    end
    
    if ismatrix(S)
        c = sum(c,1);
    else
        c = squeeze(sum(sum(c,2),1));
    end
end

function c = getSTCorr(S, stimulusType)
% Time is the last dimension.
    nt = size(S,ndims(S));
    
    % Generate the base correlation for convolution.
    cv = zeros(size(S,1), nt);
    
    switch stimulusType
        case '2-point positive'
            cv(1,2) = 1;
            cv(2,1) = 1;
        case '2-point negative'
            cv(1,2) = -1;
            cv(2,1) = 1;
        case '3-point diverging positive'
            cv(1:2,2) = 1;
            cv(2,1) = 1;
        case '3-point converging positive'
            cv(1,1:2) = 1;
            cv(2,1) = 1;
        case '3-point diverging negative'
            cv(1:2,2) = -1;
            cv(2,1) = -1;
        case '3-point converging negative'
            cv(1,1:2) = -1;
            cv(2,1) = -1;
        case 'ternary'
            cv(1,1) = 1;
            cv(2,2) = 1;
        otherwise
            cv(1,2) = 1;
            cv(2,1) = 1;
    end
    
    % Subtract the mean of the columns.
    if ~ismatrix(S) && (size(S,2) == 1)
        S = squeeze(S);
    end
    
    if ismatrix(S)
        c = conv2(S, cv);
    else
        for k = 1 : size(S,2)
            if k == 1
                c = conv2(squeeze(S(:,k,:)), cv);
            else
                c = c + conv2(squeeze(S(:,k,:)), cv);
            end
        end
    end
    
    c = sum(c,1);
    c = c(1 : nt);
end
%     c = c / (N - 1);

% Calculate the two-point correlations
% if ismatrix(S)
%     foo = (S(1:end-1,1:end-1) .* S(2:end,2:end)) + (S(1:end-1,2:end) .* S(2:end,1:end-1));
%     c2(2:end) = sum(foo,1);
% else
%     foo = (S(1:end-1,:,1:end-1) .* S(2:end,:,2:end)) + (S(1:end-1,:,2:end) .* S(2:end,:,1:end-1));
%     c2(2:end) = squeeze(sum(sum(foo,1),2));
% end
% 
% c2 = c2 / 2 / (N - 1);
% 
% c2(2:end) = c2(2:end) - mean(c2(2:end));
% 
% % Calculate the three-point correlations
% if ismatrix(S)
%     foo = (S(1:end-1,1:end-1) .* ((S(1:end-1,2:end)+S(2:end,2:end))/2)) +... 
%         (S(1:end-1,2:end) .* ((S(1:end-1,1:end-1)+S(2:end,1:end-1))/2));
%     c3(2:end) = sum(foo,1);
% else
%     foo = (S(1:end-1,:,1:end-1) .* ((S(1:end-1,:,2:end)+S(2:end,:,2:end))/2)) +... 
%         (S(1:end-1,:,2:end) .* ((S(1:end-1,:,1:end-1)+S(2:end,:,1:end-1))/2));
%     c3(2:end) = squeeze(sum(sum(foo,1),2));
% end
% 
% c3 = c3 / 2 / (N-1);
% c3(2:end) = c3(2:end) - mean(c3(2:end));