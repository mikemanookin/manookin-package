function xyMatrix = getXYDotTrajectories(stimFrames,motionPerFrame,spaceConstant,numDots,screenSize,seed,minRadius)

% Pre-allocate the x/y position matrix.
xyMatrix = zeros(stimFrames, numDots, 2);

% Seed the random number generator.
noiseStream = RandStream('mt19937ar','Seed',seed);

% Generate random initial positions for the dots.
positions = ceil(noiseStream.rand(numDots,2) .* (ones(numDots,1)*screenSize));

% Set the xyMatrix initial values.
xyMatrix(1,:,:) = positions;

% Get the diagonal indices.
idx = logical(eye(numDots));

for k = 2 : stimFrames
    % Get the pairwise distance between points.
    d = squareform(pdist(positions));
    
    % Apply space constant to get the covariance matrix.
    C = exp(-d / spaceConstant);
    % Check whether the matrix is positive definite.
%     [tmp, tf] = chol(C);
%     if ~tf
%         C = tmp;
%     end
    
    % Get the x/y shift.
    xShift = motionPerFrame * noiseStream.randn(1,numDots) * C;
    yShift = motionPerFrame * noiseStream.randn(1,numDots) * C;
    
    % Add the shifts to the current positions and iterate.
    positions = round(positions + [xShift(:) yShift(:)]);
    
    % Make sure they don't go off of the screen.
    positions(positions < 1) = 1;
    positions(positions(:,1) > screenSize(1),1) = screenSize(1);
    positions(positions(:,2) > screenSize(2),2) = screenSize(2);
    
    % Shift any dots that are overlapping.
    d = squareform(pdist(positions));
    % Give the diagonal elements a large value so they don't violate.
    d(idx) = 1e3;
    [rows,~] = find(d < minRadius);
    
    % Shift the points that are too close.
    if ~isempty(rows)
        positions(unique(rows),:) = positions(unique(rows),:) + minRadius*noiseStream.randn(length(unique(rows)),2);
    end
    
    xyMatrix(k,:,:) = positions;
end

