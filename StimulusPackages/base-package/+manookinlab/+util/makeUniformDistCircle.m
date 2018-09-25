function [M, circlePoints] = makeUniformDistCircle(M,C)
%C is contrast
diameter = size(M,1);
radius = floor(diameter/2);


X = -radius+1:radius;
Y = -radius+1:radius;
Xmat = repmat(X,2*radius,1);
Ymat = repmat(Y,2*radius,1)';
%Xmat = repmat(X,diameter,1);
%Ymat = repmat(Y,diameter,1)';

circlePoints = sqrt(Xmat.^2 + Ymat.^2)<radius;

M(M<0) = 0;

M(~circlePoints) = 0;
M_flat = M(circlePoints);

bins = [eps, prctile(M_flat,[1:1:100])];

%keyboard;
%bins = [-Inf, prctile(M_flat,50), Inf];
M_orig = M;
for i=1:length(bins)-1
    M(M_orig>bins(i) & M_orig<=bins(i+1)) = i*(C/(length(bins)-1));
%    M(M_orig>bins(i) & M_orig<=bins(i+1)) = (i-1).*C;
end
M(circlePoints) = M(circlePoints) + .5 - C/2;
M(circlePoints) = M(circlePoints) - mean(M(circlePoints)) + 0.5;
%M = M ./ (mean(M(:))./.5);