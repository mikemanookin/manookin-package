function y = sem(varargin)
% SEM Standard-error of the mean.
% y = sem(varargin)
%
% Uses the same input scheme as std and var.
% Written by Mike Manookin 1/17/2017

% Get the size
if nargin > 2
    dim = varargin{3};
else
    dim = find(size(varargin{1}) ~= 1, 1);
    if isempty(dim)
        dim = 1;
    end
end

x = varargin{1};
n = size(x,dim);

y = nanstd(x,[],dim) / sqrt(n);