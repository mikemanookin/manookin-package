function [images, blank, info] = padImagesToCommonSize(images, fillValue)
%PADIMAGESTOCOMMONSIZE Center a set of uint8 images on one common canvas.
%
% [images, blank, info] = manookinlab.util.padImagesToCommonSize(images, fillValue)
%
% Stage's stage.builtin.stimuli.Image allocates its texture at the size of
% the image it is constructed with. Later changes to imageMatrix are written
% into that texture with setSubImage at offset (0,0), so a smaller image only
% overwrites one corner (the rest keeps the previous image), and a larger one
% does not fit. Any protocol that swaps imageMatrix during a presentation
% needs every image to have the same size and channel count.
%
% This pads each image, centered, to the largest height and width in the set,
% filling with fillValue (0-1, i.e. the background intensity). Grayscale
% images are replicated to 3 channels if any image in the set is RGB. Pixel
% scale is unchanged: nothing is resized.
%
% INPUTS:
%   images    - cell array of uint8 images (HxW or HxWx3)
%   fillValue - padding intensity, 0-1
%
% OUTPUTS:
%   images - the padded images, all [H W C]
%   blank  - a uint8 [H W C] image filled with fillValue
%   info   - struct: size ([H W C]) and nPadded (images that were padded)

    h = cellfun(@(x) size(x, 1), images);
    w = cellfun(@(x) size(x, 2), images);
    c = cellfun(@(x) size(x, 3), images);
    H = max(h);
    W = max(w);
    C = max(c);

    blank = repmat(uint8(round(fillValue * 255)), H, W, C);

    for k = 1 : numel(images)
        img = images{k};
        if size(img, 3) < C
            img = repmat(img(:, :, 1), 1, 1, C);
        end
        if h(k) ~= H || w(k) ~= W
            r0 = floor((H - h(k)) / 2);
            c0 = floor((W - w(k)) / 2);
            out = blank;
            out(r0 + (1:h(k)), c0 + (1:w(k)), :) = img;
            img = out;
        end
        images{k} = img;
    end

    info.size = [H, W, C];
    info.nPadded = sum(h ~= H | w ~= W);
end
