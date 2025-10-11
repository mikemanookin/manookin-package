% function [path_dict,imagesPerDir] = read_images_from_dir(image_dir, folderList, validImageExtensions)


image_dir = '/Users/michaelmanookin/Documents/PennImageDatabase/PennImages457x286';
folderList = {'PennImages01','PennImagesTest'};
validImageExtensions = {'.png','.jpg','.jpeg','.tif','.tiff'};

% Loop through each of the folders and get the images.
% fullImagePaths = {};
% imageCount = 0;
% imagesPerDir = zeros(1,length(folderList));
% for ii = 1 : length(folderList)
%     fileFolder = folderList{ii};
%     current_directory = fullfile(image_dir, fileFolder);
%     dir_contents = dir(current_directory);
%     % Filter out hidden files.
%     dir_contents = dir_contents(~startsWith({dir_contents.name}, '.')); % Remove hidden files
%     imageDirCount=0;
%     for jj = 1 : length(dir_contents)
%         for kk = 1 : length( validImageExtensions )
%             % Ignore .DS_Store and Thumb images.
%             if ~isempty(strfind(lower(dir_contents(jj).name), validImageExtensions{kk}))
%                 imageCount = imageCount + 1;
%                 imageDirCount = imageDirCount + 1;
%                 fullImagePaths = [fullImagePaths, fullfile(current_directory,dir_contents(jj).name)]; %#ok<AGROW>
%             end
%         end
%     end
%     imagesPerDir(ii) = imageDirCount;
% end

% Get the images into a directory.
path_dict = containers.Map;

imagesPerDir = zeros(1,length(folderList));
for ii = 1 : length(folderList)
    fullImagePaths = {};
    fileFolder = folderList{ii};
    current_directory = fullfile(image_dir, fileFolder);
    dir_contents = dir(current_directory);
    % Filter out hidden files.
    dir_contents = dir_contents(~startsWith({dir_contents.name}, '.')); % Remove hidden files
    imageDirCount=0;
    for jj = 1 : length(dir_contents)
        for kk = 1 : length( validImageExtensions )
            % Ignore .DS_Store and Thumb images.
            if ~isempty(strfind(lower(dir_contents(jj).name), validImageExtensions{kk}))
                imageCount = imageCount + 1;
                imageDirCount = imageDirCount + 1;
                fullImagePaths = [fullImagePaths, fullfile(current_directory,dir_contents(jj).name)]; %#ok<AGROW>
            end
        end
    end
    imagesPerDir(ii) = imageDirCount;
    path_dict(fileFolder) = fullImagePaths;
end

