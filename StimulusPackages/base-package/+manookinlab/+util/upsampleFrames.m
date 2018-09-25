function upFrames = upsampleFrames(frames, multiple)

% Determine the dimensions.
n = ndims(frames);

if n == 2
    upFrames = zeros(size(frames,1), size(frames,2)*multiple);
    
    for frameIndex = 1 : size(frames,2)*multiple
        fIndex = ceil(frameIndex / multiple);
        upFrames(:,frameIndex) = frames(:,fIndex);
    end
    
elseif n == 3
    upFrames = zeros(size(frames,1), size(frames,2), size(frames,3)*multiple);
    
    for frameIndex = 1 : size(frames,3)*multiple
        fIndex = ceil(frameIndex / multiple);
        upFrames(:,:,frameIndex) = frames(:,:,fIndex);
    end
else
    error('Number of dimensions must be either 2 or 3!');
end
