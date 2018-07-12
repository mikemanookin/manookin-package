%% Pull van Hateren natural images...
clear all; close all; clc;
% IMAGES_DIR = 'C:\Users\Public\Documents\turner-package\resources\VHsubsample_20160105\'; % RIG PC
IMAGES_DIR            = '~/Documents/MATLAB/Analysis/NatImages/Stimuli/VHsubsample_20160105/'; %MAC
temp_names                  = GetFilenames(IMAGES_DIR,'.iml');	
for file_num = 1:size(temp_names,1)
    temp                    = temp_names(file_num,:);
    temp                    = deblank(temp);
    img_filenames_list{file_num}  = temp;
end

img_filenames_list = sort(img_filenames_list);

%% step 1: make RF components
imageScalingFactor = 3.3; %microns on retina per image pixel (3.3 um/arcmin visual angle)
NumFixations = 10000;           % how many patches to sample
% RF properties:
stimSize_microns = [1460 1100];          % Based on biggest screen in microns (2P emagin, [1440 1080]) so no fixations take you outside of image edge
FilterSize_microns = 250;                % size of patch (um). Code run-time is very sensitive to this
SubunitRadius_microns = 12;              % radius of subunit (12 um -> 48 um subunit diameter)
CenterRadius_microns = 50;              % center radius (50 um -> 200 um RF center size)

%convert to pixels:
stimSize = round(stimSize_microns / imageScalingFactor);
FilterSize = round(FilterSize_microns / imageScalingFactor);
SubunitRadius = round(SubunitRadius_microns / imageScalingFactor);
CenterRadius = round(CenterRadius_microns / imageScalingFactor);

disp(FilterSize)

% create RF component filters
% subunit locations - square grid
TempFilter = zeros(FilterSize, FilterSize);
SubunitLocations = find(rem([1:FilterSize], 2*SubunitRadius) == 0);
for x = 1:length(SubunitLocations)
    TempFilter(SubunitLocations(x), SubunitLocations) = 1;
end
SubunitIndices = find(TempFilter > 0);

% center, surround and subunit filters
for x = 1:FilterSize
    for y = 1:FilterSize
        SubunitFilter(x,y) = exp(-((x - FilterSize/2).^2 + (y - FilterSize/2).^2) / (2 * (SubunitRadius^2)));
        RFCenter(x,y) = exp(-((x - FilterSize/2).^2 + (y - FilterSize/2).^2) / (2 * (CenterRadius^2)));
    end
end

% normalize each component
RFCenter = RFCenter / sum(RFCenter(:));
SubunitFilter = SubunitFilter / sum(SubunitFilter(:));
%get weighting of each subunit output
subunitWeightings = RFCenter(SubunitIndices);

% plot RF components
figure(1); clf;
subplot(1, 2, 1);
imagesc(RFCenter);colormap gray;axis image;  hold on
subplot(1, 2, 2);
imagesc(SubunitFilter);colormap gray;axis image; hold on

%% step 2: apply to random image patches to each image

for ImageIndex = 1:length(img_filenames_list)
    ImageID = img_filenames_list{ImageIndex}(1:8);
    % Load  and plot the image to analyze
    f1=fopen([IMAGES_DIR, img_filenames_list{ImageIndex}],'rb','ieee-be');
    w=1536;h=1024;
    my_image=fread(f1,[w,h],'uint16');
    [ImageX, ImageY] = size(my_image);

    % scale image to [0 1] -- contrast, relative to mean over entire image...
    my_image_nomean = (my_image - mean(my_image(:))) ./ mean(my_image(:));

    clear RFCenterProj RFSubCenterProj Location

    %set random seed
    randSeed = 1;
    rng(randSeed);
    % choose set of random patches and measure RF components
    for patch = 1:NumFixations

        % choose location
        x = round(stimSize(1)/2 + (ImageX - stimSize(1))*rand);
        y = round(stimSize(2)/2 + (ImageY - stimSize(2))*rand);
        Location(patch,:) = [x, y];

        % get patch
        ImagePatch = my_image_nomean(x-FilterSize/2+1:x+FilterSize/2,y-FilterSize/2+1:y+FilterSize/2);

        % convolve patch with subunit filter
        ImagePatch = conv2(ImagePatch, SubunitFilter, 'same');  

        % activation of each subunit
        subunitActivations = ImagePatch(SubunitIndices);

        % Linear center:
        LinearResponse = sum(subunitActivations .* subunitWeightings);
        RFCenterProj(patch) = max(LinearResponse,0); %threshold summed input

        % Subunit center:
        subunitOutputs = subunitActivations;
        subunitOutputs(subunitOutputs<0) = 0; %threshold each subunit
        RFSubCenterProj(patch) = sum(subunitOutputs.* subunitWeightings);

        if (rem(patch, 500) == 0)
            fprintf(1, '%d ', patch);
        end
    end
    imageData.(ImageID).location = Location;
    imageData.(ImageID).LnModelResponse = RFCenterProj;
    imageData.(ImageID).SubunitModelResponse = RFSubCenterProj;
    % calculate differences
    imageData.(ImageID).responseDifferences = ...
         imageData.(ImageID).SubunitModelResponse - imageData.(ImageID).LnModelResponse;
     clc; 
     disp(num2str(ImageIndex))
end
modelParameters.randSeed = randSeed;
modelParameters.imageScalingFactor = imageScalingFactor;
modelParameters.NumFixations = NumFixations;
modelParameters.FilterSize_microns = FilterSize_microns;
modelParameters.SubunitRadius_microns = SubunitRadius_microns;
modelParameters.CenterRadius_microns = CenterRadius_microns;
modelParameters.FilterSize = FilterSize;
modelParameters.SubunitRadius = SubunitRadius;
modelParameters.CenterRadius = CenterRadius;

save('NaturalImageFlashLibrary_072216.mat','imageData','modelParameters');

%% Code like the following in protocols to do biased sampling:
noBins = 50; %from no. image patches to show
figure(3); clf; subplot(2,2,1)
hist(imageData.(ImageID).responseDifferences,noBins);
subplot(2,2,2); plot(imageData.(ImageID).SubunitModelResponse,imageData.(ImageID).LnModelResponse,'ko')

[N, edges, bin] = histcounts(imageData.(ImageID).responseDifferences,noBins);
populatedBins = unique(bin);

%pluck one patch from each bin
pullInds = arrayfun(@(b) find(b == bin,1),populatedBins);

figure(3); subplot(2,2,3)
hist(imageData.(ImageID).responseDifferences(pullInds),noBins)
subplot(2,2,4); plot(imageData.(ImageID).SubunitModelResponse(pullInds),imageData.(ImageID).LnModelResponse(pullInds),'ko')

%%
figure(2); clf;  
imagesc((my_image').^0.3);colormap gray;axis image; axis off; hold on;
plot(imageData.(ImageID).location(:,1),imageData.(ImageID).location(:,2),'r.');