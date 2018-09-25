function y = outputNonlinearity(vars, x)
%

if length(vars) == 4
    y = vars(1)*normcdf(vars(2)*x+vars(3), 0, 1) + vars(4);
else
    y = vars(1)*normcdf(vars(2)*x+vars(3), 0, 1);
end

