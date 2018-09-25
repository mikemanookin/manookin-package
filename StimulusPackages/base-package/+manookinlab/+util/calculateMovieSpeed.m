function [spd,vx,vy,sx,sy,ang] = calculateMovieSpeed(M)
% 
% https://people.ece.cornell.edu/land/PROJECTS/MotionDamian/

if ismatrix(M)
    [spd,vx,vy,sx,sy,ang] = calculateMovieSpeed2D(M);

elseif ndims(M) == 3
    [spd,vx,vy,sx,sy,ang] = calculateMovieSpeed3D(M);
end

end

function [spd,vx,vy,sx,sy,ang] = calculateMovieSpeed2D(M)
    [a,nT]=size(M);
%     resRange = fix(log2(a))-1;
    [gx,gt] = gradient(M);

    % vy and ang don't make sense.
    vy = [];
    ang = [];
    sy = [];

    % Allocate memory.
    vx = zeros(size(M));
    spd = zeros(size(M));
    sx = zeros(1, nT);
    for i=1:nT
        nml = gx(:,i).^2;
        nml((nml<.00001)) = 1; %does not affect result because gx,gy are zero
        vx(:,i) = gt(:,i).*gx(:,i) ./nml ;
        spd(:,i) = sqrt(vx(:,i).^2);

        sx(i)=sum(vx(:,i))/a;
    end
end

% 3-D
function [spd,vx,vy,sx,sy,ang] = calculateMovieSpeed3D(M)
    [a,b,nT]=size(M);
    %     resRange = fix(log2(min(a,b)))-1;
    [gx,gy,gt] = gradient(M);
    % Allocate memory.
    vx = zeros(size(M));
    vy = zeros(size(M));
    spd = zeros(size(M));
    sx = zeros(1, nT);
    sy = zeros(1, nT);
    ang = zeros(1, nT);
    for i=1:nT
        nml = (gx(:,:,i).^2 + gy(:,:,i).^2);
        nml((nml<.00001)) = 1; %does not affect result because gx,gy are zero
        vx(:,:,i) = gt(:,:,i).*gx(:,:,i) ./nml ;
        vy(:,:,i) = gt(:,:,i).*gy(:,:,i) ./nml ;
        spd(:,:,i) = sqrt(vx(:,:,i).^2 + vy(:,:,i).^2) ;

        sx(i)=sum(sum(vx(:,:,i)))/(a*b);
        sy(i)=sum(sum(vy(:,:,i)))/(a*b);
        ang(i)=(atan2(sy(i),sx(i)));
    end
end