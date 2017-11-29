function params = fitAnnulusAreaSum(radii,responses,params0)

LB = [0, 0, 0, 0]; UB = [1e4 2e3 1e4 5e3];
fitOptions = optimset('MaxIter',2000,'MaxFunEvals',600*length(LB),'Display','off');

[params, ~, ~]=lsqcurvefit(@annulusAreaSummation,params0,radii,responses,LB,UB,fitOptions);