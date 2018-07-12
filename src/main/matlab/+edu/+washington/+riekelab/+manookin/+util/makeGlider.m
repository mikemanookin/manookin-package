function S = makeGlider(xsize,ysize,tsize,glider,parity,seed)
%Glider stimulus generation
%   S = makeGlider(xsize,ysize,tsize,rule,parity);
%   Input:
%     xsize, ysize, tsize: size of the stimulus.
%     glider: an N-by-3 array, specifying the shape of the N-element glider.
%         Each row is the (x,y,t) coordinates of a check in the glider.
%     parity: can be 0 or 1, constrains the number of black checks in the glider to be even or odd
%   Out put:
%     a 3-dimensional logic array of size (xsize,ysize,tsize), 0 = black, 1 = white
%   Example:
%     All stimuli used in our psychophysics have xsize = ysize = 64, tsize = 20, parity = 0 or 1
%          S = makeGlider(64,64,20,glider,parity);
%     Each glider has a different ruleset.
%          Figure 1 : glider = [0 0 0;0 1 0;1 0 1]
%          Figure 2A: glider = [0 0 0;1 0 0;1 0 1;2 0 1]
%          Figure 2B: glider = [0 0 0;0 0 1;1 0 1;1 0 2]
%          Figure 3A: glider = [0 0 0;1 0 0;0 1 0;1 0 1]
%          Figure 3B: glider = [0 0 0;1 0 0;1 0 1]

if ((parity ~= 0) && (parity ~= 1)); error('Parity must be 0 or 1!'); end

[n, m] = size(glider); % n is the number of checks in the glider
if (m~=3); error('glider must be an N-by-3 array!'); end

glider = glider - ones(n,1) * min(glider); % make sure glider is tightly 
                                           % confined in the box defined
                                           % by (0,0,0) and max(glider)
glider = sortrows(glider,[3 2 1]);
glider_root = glider(n,:);
glider = glider - ones(n,1) * glider_root;
glider_max = max(glider);
glider = glider(1:n-1,:);                  % remove the root check
                                           % since it is to be colored

if ~exist('seed','var')
    seed = RandStream.shuffleSeed;
end
                                           
noiseStream = RandStream('mt19937ar', 'Seed', seed);
S = (noiseStream.rand(xsize, ysize, tsize) > 0.5);

for it = glider_root(3)+1 : tsize-glider_max(3)
    for iy = glider_root(2)+1 : ysize-glider_max(2)
        for ix = glider_root(1)+1 : xsize-glider_max(1)
            nblack = 0; %counter for black checks in the glider
            
            % loop though all glider checks other than the root check
            for in = 1 : n-1
                nblack = nblack + (1 - S(ix+glider(in,1), ...
                                         iy+glider(in,2), ...
                                         it+glider(in,3)));
            end
            
            % determine the color of the root check
            if (mod(nblack,2)==parity)
                S(ix,iy,it) = 1;
            else
                S(ix,iy,it) = 0;
            end
        end
    end
end
