function M = getXYDotTrajectories(stimFrames,motionPerFrame,spaceConstant,numDots,screenSize,seed,correlationFrames,splitContrasts)

% Pre-allocate the x/y position matrix.
M = zeros([screenSize,stimFrames]);

% Make every other dot alternate black/white
if splitContrasts
    dotContrasts = 2*mod(1:numDots,2)-1;
else
    dotContrasts = ones(1,numDots);
end

% Seed the random number generator.
noiseStream = RandStream('mt19937ar','Seed',seed);

% Generate random initial positions for the dots.
positions = ceil(noiseStream.rand(numDots,2) .* (ones(numDots,1)*screenSize));

for k = 1 : stimFrames
    
    if mod(k+1,correlationFrames) == 0
        % Generate random initial positions for the dots.
        positions = ceil(noiseStream.rand(numDots,2) .* (ones(numDots,1)*screenSize));
        xShift = motionPerFrame * noiseStream.randn(1,numDots);
        yShift = motionPerFrame * noiseStream.randn(1,numDots);
    else
        % Get the pairwise distance between points.
        d = squareform(pdist(positions));

        % Apply space constant to get the covariance matrix.
        C = exp(-d / spaceConstant);

        % Get the x/y shift.
        xShift = motionPerFrame * noiseStream.randn(1,numDots) * C;
        yShift = motionPerFrame * noiseStream.randn(1,numDots) * C;
    end
    
    % Add the shifts to the current positions and iterate.
    positions = round(positions + [xShift(:) yShift(:)]);
    
    positions = round(positions);
    

    % Make sure they don't go off of the screen.
    positions(positions(:,1) < 1, 1) = -positions(positions(:,1) < 1, 1);
    positions(positions(:,2) < 1, 2) = -positions(positions(:,2) < 1, 2);
    
    positions(positions(:,1) > screenSize(1),1) = screenSize(1) - (positions(positions(:,1) > screenSize(1),1) - screenSize(1));
    positions(positions(:,2) > screenSize(2),2) = screenSize(2) - (positions(positions(:,2) > screenSize(2),2) - screenSize(2));
    
    positions(positions <= 0) = 1;
    
    mtmp = zeros(screenSize);
    for m = 1 : numDots
%         if all(positions(m,:) >= 1, 'all') && (positions(m,1) <= screenSize(1)) && (positions(m,2) <= screenSize(2))
            mtmp(positions(m,1),positions(m,2)) = dotContrasts(m);
%         end
    end
    M(:,:,k) = mtmp;
end

