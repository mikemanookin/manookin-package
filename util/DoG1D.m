function y = DoG1D(v, x)
%
%
% v(1) = Kc
% v(2) = Rc
% v(3) = Ks
% v(4) = Rs
% v(5) = baseline response

% x = 1./x;

dx=0.0001;

y = zeros(size(x));
for k = 1 : length(x)
    y(k) = v(5)+(v(1)*sum(exp(-(2*(0:dx:x(k))/v(2)).^2)) - v(3)*sum(exp(-(2*(0:dx:x(k))/v(4)).^2)))*dx;
end

