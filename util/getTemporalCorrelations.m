function [c2,c3] = getTemporalCorrelations(S)

if ismatrix(S)
    N = size(S,1);
else
    N = size(S,1)*size(S,2);
end

c2 = zeros(1,size(S,ndims(S)));
c3 = zeros(1,size(S,ndims(S)));

% Calculate the two-point correlations
if ismatrix(S)
    foo = (S(1:end-1,1:end-1) .* S(2:end,2:end)) + (S(1:end-1,2:end) .* S(2:end,1:end-1));
    c2(2:end) = sum(foo,1);
else
    foo = (S(:,1:end-1,1:end-1) .* S(:,2:end,2:end)) + (S(:,1:end-1,2:end) .* S(:,2:end,1:end-1));
    c2(2:end) = squeeze(sum(sum(foo,1),2));
end

c2 = c2 / 2 / (N - 1);

% c2(2:end) = c2(2:end) - mean(c2(2:end));

% Calculate the three-point correlations
if ismatrix(S)
    foo = (S(1:end-1,1:end-1) .* ((S(1:end-1,2:end)+S(2:end,2:end))/2)) +... 
        (S(1:end-1,2:end) .* ((S(1:end-1,1:end-1)+S(2:end,1:end-1))/2));
    c3(2:end) = sum(foo,1);
else
    foo = (S(:,1:end-1,1:end-1) .* ((S(:,1:end-1,2:end)+S(:,2:end,2:end))/2)) +... 
        (S(:,1:end-1,2:end) .* ((S(:,1:end-1,1:end-1)+S(:,2:end,1:end-1))/2));
    c3(2:end) = squeeze(sum(sum(foo,1),2));
end

c3 = c3 / 2 / (N-1);
% c3(2:end) = c3(2:end) - mean(c3(2:end));


