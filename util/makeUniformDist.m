function M = makeUniformDist(M,C)
%C is contrast
M_flat = M(:);
bins = [-Inf prctile(M_flat,[1:1:100])];
%bins = [-Inf, prctile(M_flat,50), Inf];
M_orig = M;
for i=1:length(bins)-1
    M(M_orig>bins(i) & M_orig<=bins(i+1)) = i*(C/(length(bins)-1));
%    M(M_orig>bins(i) & M_orig<=bins(i+1)) = (i-1).*C;
end
M = M + .5 - C/2;
M = M - mean(M(:)) + 0.5;
%M = M ./ (mean(M(:))./.5);