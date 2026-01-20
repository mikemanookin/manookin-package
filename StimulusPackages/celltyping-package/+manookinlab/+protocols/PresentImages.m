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
            
            % Calcualate the number of flash and gap frames.
            obj.expectedRefreshRate = obj.rig.getDevice('Stage').getExpectedRefreshRate();
            obj.preFrames = round((obj.preTime * 1e-3) * obj.expectedRefreshRate);
            obj.flashFrames = round((obj.flashTime * 1e-3) * obj.expectedRefreshRate);
            obj.gapFrames = round((obj.gapTime * 1e-3) * obj.expectedRefreshRate);
            obj.tailFrames = round((obj.tailTime * 1e-3) * obj.expectedRefreshRate);
            obj.stimFrames = round((obj.flashFrames + obj.gapFrames) * obj.imagesPerEpoch);
            
            % General directory
            try
                image_dir = obj.rig.getDevice('Stage').getConfigurationSetting('local_image_directory');
                if isempty(image_dir)
                    image_dir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\';
                end
            catch
                image_dir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\';
            end
            
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
        disp(['Organizing image sequences for ', num2str(nFolders), ' folders.']);

        for ii = 1 : nFolders
            nImgs = obj.imagesPerDir(ii);
            
            % Compute epochs one repeat of all images would take.
            nEpochsForFolder = ceil(nImgs / obj.imagesPerEpoch);
            % Generate a random or sequential order of all images in the folder
            if obj.randomize
                perm = randperm(nImgs);
            else
                perm = 1:nImgs;
            end

            % Pad with wrap-around for last epoch if needed.
            nNeeded = nEpochsForFolder * obj.imagesPerEpoch;

            if nImgs < nNeeded
                nToPad = nNeeded - nImgs;
                perm = [perm, perm(1:nToPad)];
            end
            perm = perm(1:nNeeded);

            % Reshape into [nEpochsForFolder x imagesPerEpoch]
            obj.sequence{ii} = reshape(perm, nEpochsForFolder, obj.imagesPerEpoch);
            disp(['Folder ', num2str(ii), ': ', num2str(nImgs), ' images, organized into ', num2str(nEpochsForFolder), ' epochs.']);
        end
    end

        
        function p = createPresentation(obj)
            % Stage presets
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();     
            totalTimePerEpoch = ceil((obj.preFrames + obj.stimFrames + obj.tailFrames)/obj.expectedRefreshRate);
            p = stage.core.Presentation(totalTimePerEpoch);
            
            p.setBackgroundColor(obj.backgroundIntensity)   % Set background intensity
            
            % Prep to display image
            scene = stage.builtin.stimuli.Image(obj.imageMatrix{1});
            scene.size = [size(obj.imageMatrix{1},2),size(obj.imageMatrix{1},1)]*obj.magnificationFactor; % Retain aspect ratio.
            scene.position = canvasSize/2;
            
            % Use linear interpolation when scaling the image
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);

            % Only allow image to be visible during specific time
            p.addStimulus(scene);
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.frame >= obj.preFrames && state.frame < obj.preFrames + obj.stimFrames);
            p.addController(sceneVisible);

            % Control which image is visible.
            imgValue = stage.builtin.controllers.PropertyController(scene, ...
                'imageMatrix', @(state)setImage(obj, state.frame - obj.preFrames));
            % Add the controller.
            p.addController(imgValue);

%             function s = setImage(obj, time)
%                 img_index = floor( time / ((obj.flashTime+obj.gapTime)*1e-3) ) + 1;
%                 if img_index < 1 || img_index > obj.imagesPerEpoch
%                     s = obj.backgroundImage;
%                 elseif (time >= ((obj.flashTime+obj.gapTime)*1e-3)*(img_index-1)) && (time <= (((obj.flashTime+obj.gapTime)*1e-3)*(img_index-1)+obj.flashTime*1e-3))
%                     s = obj.imageMatrix{img_index};
%                 else
%                     s = obj.backgroundImage;
%                 end
%             end
            
            function s = setImage(obj, frame)
                img_index = floor( frame / (obj.flashFrames+obj.gapFrames) ) + 1;
%                 img_index = floor( time / ((obj.flashTime+obj.gapTime)*1e-3) ) + 1;
                if img_index < 1 || img_index > obj.imagesPerEpoch
                    s = obj.backgroundImage;
                elseif (frame >= (obj.flashFrames+obj.gapFrames)*(img_index-1)) && (frame <= ((obj.flashFrames+obj.gapFrames)*(img_index-1)+obj.flashFrames))
                    s = obj.imageMatrix{img_index};
                else
                    s = obj.backgroundImage;
                end
            end
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

            % Get the correct row for this epoch
            epochIdxForFolder = floor(obj.numEpochsCompleted / length(obj.folderList)) + 1;
            seq = obj.sequence{current_folder_index};
            % If epochIdxForFolder exceeds the number of rows, regenerate the sequence and wrap around
            if epochIdxForFolder > size(seq, 1)
                obj.organize_image_sequences(obj.image_parent_dir);
                seq = obj.sequence{current_folder_index};
                epochIdxForFolder = mod(epochIdxForFolder-1, size(seq, 1)) + 1;
            end
            img_indices = seq(epochIdxForFolder, :);
            
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
            
            % Get the magnification factor to retain aspect ratio.
            if obj.scaleToScreenSize
                obj.magnificationFactor = ceil( max(obj.canvasSize(2)/size(obj.imageMatrix{1},1),obj.canvasSize(1)/size(obj.imageMatrix{1},2)) );
            else
                obj.magnificationFactor = obj.pixelSize / obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            end
            
            % Create the background image.
            obj.backgroundImage = ones(size(myImage))*obj.backgroundIntensity;
            obj.backgroundImage = uint8(obj.backgroundImage*255);
            epoch.addParameter('folder', folderName);
            epoch.addParameter('imageName', imageName);
            disp(['Presenting images from folder: ', folderName]);
            disp(['Images: ', imageName]);
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
