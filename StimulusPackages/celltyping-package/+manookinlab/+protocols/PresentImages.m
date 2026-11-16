% Loads and presents image files that are contained within a directory indicated
% with the 'fileFolder' property.
%
% To determine the 'numberOfAverages' needed to present all of the images in the 
% directory once, you would divide the number of images by the 'imagesPerEpoch'
% property. If there are 1000 images and 'imagesPerEpoch' is 100, then the 
% 'numberOfAverages' needed to present each image once is 1000/100 = 10.
%
% Analysis note:
% Because we are presenting multiple images per epoch, the epoch property imageName 
% that saves the image presented is now a list of all images presented in the correct 
% order with each image delimited by a comma. This should make analyzing the data 
% straightforward.
%
% Also, there is a magnificationFactor property that records the degree to which the
% images were scaled in order to fill the screen.


classdef PresentImages < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                         % Output amplifier
        preTime     = 250           % Pre time in ms
        flashTime   = 100           % Time to flash each image in ms
        gapTime     = 400           % Gap between images in ms
        tailTime    = 250           % Tail time in ms
        imagesPerEpoch = 115        % Number of images to flash on each epoch
        scaleToScreenSize = true    % Boolean scale to the screen size
        pixelSize = 1.0             % Pixel size in microns (used if scaleToScreenSize is false)
        fileFolders    = 'ImageNet01,ImageNetTest' % List of folders containing the images separated by , or ;
        backgroundIntensity = 0.45; % 0 - 1 (corresponds to image intensities in folder)
        innerMaskDiameter = 0       % Inner mask diameter (in microns), not used if 0.
        outerMaskDiameter = 0       % Outer mask diameter (in microns), not used if 0.
        randomize = true;           % Whether to randomize the order of images shown
        onlineAnalysis = 'none'     % Type of online analysis
        numberOfAverages = uint16(10) % Number of epochs to queue
    end

    properties (Dependent)
        stimTime
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'}) 
        sequence
        image_parent_dir
        imagePaths
        imageMatrix
        backgroundImage
        directory
        totalRuns
        image_name
        magnificationFactor
        folderList
        path_dict
        imagesPerDir
        fullImagePaths
        validImageExtensions = {'.png','.jpg','.jpeg','.tif','.tiff'}
        expectedRefreshRate
        monitorRefreshRate
        preFrames
        tailFrames
        stimFrames
        flashFrames
        gapFrames
        innerMaskRadiusPix
        outerMaskRadiusPix
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            if ~obj.isMeaRig
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            end

            % Inner and Outer masks in pixels.
            obj.innerMaskRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.innerMaskDiameter)/2.0;
            obj.outerMaskRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.outerMaskDiameter)/2.0;
            
            % Calcualate the number of flash and gap frames. Not every Stage
            % device has getExpectedRefreshRate (e.g. MicrodisplayDevice);
            % fall back to the monitor rate for it, not to a fixed 60 Hz.
            stageDev = obj.rig.getDevice('Stage');
            try
                obj.monitorRefreshRate = stageDev.getMonitorRefreshRate();
            catch x
                obj.monitorRefreshRate = 60.0;
                warning('PresentImages:refreshRate', ...
                    'getMonitorRefreshRate failed (%s); assuming 60 Hz.', x.message);
            end
            try
                obj.expectedRefreshRate = stageDev.getExpectedRefreshRate();
            catch
                obj.expectedRefreshRate = obj.monitorRefreshRate;
            end
            obj.preFrames = round((obj.preTime * 1e-3) * obj.expectedRefreshRate);
            obj.flashFrames = round((obj.flashTime * 1e-3) * obj.expectedRefreshRate);
            obj.gapFrames = round((obj.gapTime * 1e-3) * obj.expectedRefreshRate);
            obj.tailFrames = round((obj.tailTime * 1e-3) * obj.expectedRefreshRate);
            obj.stimFrames = round((obj.flashFrames + obj.gapFrames) * obj.imagesPerEpoch);
            
            % General directory: the Stage device's 'local_image_directory'
            % setting if the rig defines it, otherwise the default below.
            image_dir = '';
            try
                image_dir = stageDev.getConfigurationSetting('local_image_directory');
            catch
            end
            if isempty(image_dir)
                image_dir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\';
            end
            if exist(image_dir, 'dir') ~= 7
                error('PresentImages:noImageDir', ...
                    ['Image directory not found: %s\nSet it for this rig with ' ...
                     'addConfigurationSetting(''local_image_directory'', ''<path>'') ' ...
                     'on the Stage device in the rig description.'], image_dir);
            end
            fprintf('PresentImages: images from %s (refresh %.3g Hz, expected %.3g Hz)\n', ...
                image_dir, obj.monitorRefreshRate, obj.expectedRefreshRate);
            
            % Get the list of file folders.
            if isa(obj.fileFolders, 'cell')
                obj.folderList = obj.fileFolders;
            elseif isa(obj.fileFolders, 'char')
                if ~isempty(strfind(obj.fileFolders,';'))
                    obj.folderList = strsplit(obj.fileFolders,';');
                elseif ~isempty(strfind(obj.fileFolders,','))
                    obj.folderList = strsplit(obj.fileFolders,',');
                else
                    obj.folderList = { obj.fileFolders };
                end
            else % Need to throw an error here...
            end
            
            % Loop through each of the folders and get the images.
            obj.image_parent_dir = image_dir;
            obj.organize_image_sequences(obj.image_parent_dir);
        end

    function organize_image_sequences(obj, image_dir)

        [obj.path_dict, obj.imagesPerDir] = manookinlab.util.read_images_from_dir(image_dir, obj.folderList, obj.validImageExtensions);
        
        nFolders = length(obj.folderList);
        obj.sequence = cell(1, nFolders); % One cell per folder

        % Calculate how many epochs each folder will be used
        nEpochsForFolder = ceil(double(obj.numberOfAverages) / nFolders);

        for ii = 1:nFolders   
            nImgs = obj.imagesPerDir(ii);
            assert(nImgs > 0, ['No images found in folder: ', obj.folderList{ii}]);
            
            % Number of image-trials needed to fill each epoch for this folder
            nNeeded = nEpochsForFolder * obj.imagesPerEpoch;

            % Typically will have less images than needed, so 
            % repeat the sequence as many times as needed.
            if nImgs < nNeeded
                nRepeats = ceil(nNeeded / nImgs);
                perm = [];
                for jj = 1:nRepeats
                    if obj.randomize
                        perm = [perm, randperm(nImgs)]; %#ok<AGROW>
                    else
                        perm = [perm, 1:nImgs]; %#ok<AGROW>
                    end
                end
            elseif nImgs >= nNeeded
                % If more images than can be covered across epochs,
                if obj.randomize
                    perm = randperm(nImgs);
                else
                    perm = 1:nImgs;
                end
            end
            perm = perm(1:nNeeded);

            % Reshape into [imagesPerEpoch x nEpochsForFolder] so that the sequence 
            % progresses across rows (i.e. imagesPerEpoch) for each epoch before moving to the next epoch (next column).
            obj.sequence{ii} = reshape(perm, obj.imagesPerEpoch, nEpochsForFolder);
        end
    end

        
        function p = createPresentation(obj)
            % Stage presets
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();     
            % Total time based on monitor refresh rate as that's used by the Player to determine number of frames delivered.
            totalTimePerEpoch = ceil((obj.preFrames + obj.stimFrames + obj.tailFrames)/obj.monitorRefreshRate);
            p = stage.core.Presentation(totalTimePerEpoch);
            
            p.setBackgroundColor(obj.backgroundIntensity)   % Set background intensity
            
            % Prep to display image. All images in obj.imageMatrix share one
            % size (see prepareEpoch), which Stage's Image stimulus requires.
            scene = stage.builtin.stimuli.Image(obj.imageMatrix{1});
            scene.size = [size(obj.imageMatrix{1},2),size(obj.imageMatrix{1},1)]*obj.magnificationFactor; % Retain aspect ratio.
            scene.position = canvasSize/2;
            
            % Use linear interpolation when scaling the image
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);

            % The controllers below capture plain local copies of what they
            % need rather than obj. A closure over obj ships the whole
            % protocol object to the Stage server, which then rebuilds it
            % from whatever PresentImages class definition IT has loaded --
            % if that copy is stale, its properties come back empty and the
            % presentation fails on the server.
            preFrames = obj.preFrames;
            stimFrames = obj.stimFrames;
            flashFrames = obj.flashFrames;
            cycleFrames = obj.flashFrames + obj.gapFrames;
            nImages = obj.imagesPerEpoch;
            frames = [obj.imageMatrix(1:nImages), {obj.backgroundImage}];  % last entry = blank

            % Only allow image to be visible during specific time
            p.addStimulus(scene);
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.frame >= preFrames && state.frame < preFrames + stimFrames);
            p.addController(sceneVisible);

            % Control which image is visible: image k during the first
            % flashFrames+1 frames of cycle k (same timing as before), the
            % blank image otherwise.
            showing = @(f) f >= 0 && f < nImages*cycleFrames && mod(f, cycleFrames) <= flashFrames;
            frameIndex = @(f) showing(f) * (floor(f/cycleFrames) + 1 - (nImages + 1)) + (nImages + 1);
            imgValue = stage.builtin.controllers.PropertyController(scene, ...
                'imageMatrix', @(state)frames{frameIndex(state.frame - preFrames)});
            % Add the controller.
            p.addController(imgValue);
            % Create the inner mask.
            if (obj.innerMaskRadiusPix > 0)
                p.addStimulus(obj.makeInnerMask());
            end
            
            % Create the outer mask.
            if (obj.outerMaskRadiusPix > 0)
                p.addStimulus(obj.makeOuterMask());
            end
        end
        
        function mask = makeOuterMask(obj)
            mask = stage.builtin.stimuli.Rectangle();
            mask.color = obj.backgroundIntensity;
            mask.position = obj.canvasSize/2;
            mask.orientation = 0;
            mask.size = 2 * max(obj.canvasSize) * ones(1,2);
            sc = obj.outerMaskRadiusPix*2 / (2*max(obj.canvasSize));
            m = stage.core.Mask.createCircularAperture(sc);
            mask.setMask(m);
        end
        
        function mask = makeInnerMask(obj)
            mask = stage.builtin.stimuli.Ellipse();
            mask.radiusX = obj.innerMaskRadiusPix;
            mask.radiusY = obj.innerMaskRadiusPix;
            mask.color = obj.backgroundIntensity;
            mask.position = obj.canvasSize/2;
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Remove the Amp responses if it's an MEA rig.
            if obj.isMeaRig
                amps = obj.rig.getDevices('Amp');
                for ii = 1:numel(amps)
                    if epoch.hasResponse(amps{ii})
                        epoch.removeResponse(amps{ii});
                    end
                    if epoch.hasStimulus(amps{ii})
                        epoch.removeStimulus(amps{ii});
                    end
                end
            end

            current_folder_index = mod(obj.numEpochsCompleted, length(obj.folderList)) + 1;
            folderName = obj.folderList{ current_folder_index };
            obj.fullImagePaths = obj.path_dict( folderName );

            % Get the correct column for this epoch
            epochIdxForFolder = floor(obj.numEpochsCompleted / length(obj.folderList)) + 1;
            seq = obj.sequence{current_folder_index};
            img_indices = seq(:, epochIdxForFolder);
            
            % Load the images.
            obj.imageMatrix = cell(1, obj.imagesPerEpoch);
            folderName = '';
            imageName = ''; % Concatenate the image names separated by a comma.
            
            for ii = 1 : obj.imagesPerEpoch
                img_index = img_indices(ii);
                s = strsplit(obj.fullImagePaths{img_index}, filesep);
                obj.image_name = s{end};
                
                % Load the image.
                myImage = imread(obj.fullImagePaths{img_index});
                obj.imageMatrix{ii} = uint8(myImage);
                folderName = [folderName, s{end-1}]; %#ok<AGROW>
                imageName = [imageName, obj.image_name]; %#ok<AGROW>
                if ii < obj.imagesPerEpoch
                    folderName = [folderName, ',']; %#ok<AGROW>
                    imageName = [imageName, ',']; %#ok<AGROW>
                end
            end
            
            % Put every image on one common canvas (centered, padded with the
            % background). Stage's Image stimulus sizes its texture from the
            % first image and writes later ones into it at the corner, so a
            % folder with mixed image sizes otherwise shows a smaller image
            % in one corner over leftovers of the previous one.
            [obj.imageMatrix, obj.backgroundImage, padInfo] = ...
                manookinlab.util.padImagesToCommonSize(obj.imageMatrix, obj.backgroundIntensity);
            if padInfo.nPadded > 0
                warning('PresentImages:mixedSizes', ...
                    '%d of %d images in this epoch were padded to %dx%d (folder has mixed image sizes).', ...
                    padInfo.nPadded, obj.imagesPerEpoch, padInfo.size(1), padInfo.size(2));
            end
            
            % Get the magnification factor to retain aspect ratio.
            if obj.scaleToScreenSize
                obj.magnificationFactor = ceil( max(obj.canvasSize(2)/padInfo.size(1),obj.canvasSize(1)/padInfo.size(2)) );
            else
                obj.magnificationFactor = obj.pixelSize / obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            end
            epoch.addParameter('imageHeight', padInfo.size(1));
            epoch.addParameter('imageWidth', padInfo.size(2));
            epoch.addParameter('folder', folderName);
            epoch.addParameter('imageName', imageName);
            epoch.addParameter('magnificationFactor', obj.magnificationFactor);
            epoch.addParameter('flashFrames', obj.flashFrames);
            epoch.addParameter('gapFrames', obj.gapFrames);
            epoch.addParameter('preFrames', obj.preFrames);
            epoch.addParameter('tailFrames', obj.tailFrames);
            epoch.addParameter('stimFrames', obj.stimFrames);
        end

        function stimTime = get.stimTime(obj)
            stimTime = obj.imagesPerEpoch * (obj.flashTime + obj.gapTime);
        end
        
        function a = get.amp2(obj)
            amps = obj.rig.getDeviceNames('Amp');
            if numel(amps) < 2
                a = '(None)';
            else
                i = find(~ismember(amps, obj.amp), 1);
                a = amps{i};
            end
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
