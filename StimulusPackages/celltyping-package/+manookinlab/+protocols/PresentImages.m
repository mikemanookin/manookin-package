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
        fileFolders    = 'ImageNet01,ImageNetTest' % List of folders containing the images separated by , or ;
        backgroundIntensity = 0.45; % 0 - 1 (corresponds to image intensities in folder)
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
        imagePaths
        imageMatrix
        backgroundImage
        directory
        totalRuns
        image_name
        magnificationFactor
        folderList
        fullImagePaths
        validImageExtensions = {'.png','.jpg','.jpeg','.tif','.tiff'}
        flashFrames
        gapFrames
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
            
            % Calcualate the number of flash and gap frames.
            obj.flashFrames = round(obj.flashTime * 1e-3 * 60);
            obj.gapFrames = round(obj.gapTime * 1e-3 * 60);
            
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
            obj.fullImagePaths = {};
            imageCount = 0;
            imagesPerDir = zeros(1,length(obj.folderList));
            for ii = 1 : length(obj.folderList)
                fileFolder = obj.folderList{ii};
                current_directory = fullfile(image_dir, fileFolder);
                dir_contents = dir(current_directory);
                imageDirCount=0;
                for jj = 1 : length(dir_contents)
                    for kk = 1 : length( obj.validImageExtensions )
                        if ~isempty(strfind(dir_contents(jj).name, obj.validImageExtensions{kk}))
                            imageCount = imageCount + 1;
                            imageDirCount = imageDirCount + 1;
                            obj.fullImagePaths = [obj.fullImagePaths, fullfile(current_directory,dir_contents(jj).name)];
                        end
                    end
                end
                imagesPerDir(ii) = imageDirCount;
            end
            % Get the numbrer of repetitions per image.
            num_reps = ceil(double(obj.numberOfAverages)/size(obj.fullImagePaths,1)*obj.imagesPerEpoch);
            
            % Make sure that you get through every image in the folder
            % before moving on to the next one, even if randomizing order.
            if obj.randomize
                obj.sequence = []; %zeros(1,obj.numberOfAverages*obj.imagesPerEpoch);
                for ii = 1 : num_reps
                    for jj = 1 : length(obj.folderList)
                        if jj > 1
                            count_offset = sum(imagesPerDir(1:jj-1));
                        else
                            count_offset = 0;
                        end
                        seq = randperm(imagesPerDir(jj)) + count_offset;
                        obj.sequence = [obj.sequence, seq];
                    end
                end
                obj.sequence = obj.sequence(1:obj.numberOfAverages*obj.imagesPerEpoch);
            else
                obj.sequence = (1:length(obj.fullImagePaths))' * ones(1,num_reps);
                obj.sequence = obj.sequence(:)';
            end
        end

        
        function p = createPresentation(obj)
            % Stage presets
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();     
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            
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
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);

            % Control which image is visible.
%             imgValue = stage.builtin.controllers.PropertyController(scene, ...
%                 'imageMatrix', @(state)setImage(obj, state.time - obj.preTime*1e-3));
            preF = floor(obj.preTime*1e-3 * 60);
            imgValue = stage.builtin.controllers.PropertyController(scene, ...
                'imageMatrix', @(state)setImage(obj, state.frame - preF));
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
            
            current_index = mod(obj.numEpochsCompleted*obj.imagesPerEpoch,length(obj.sequence));
            % Load the images.
            obj.imageMatrix = cell(1, obj.imagesPerEpoch);
            folderName = '';
            imageName = ''; % Concatenate the image names separated by a comma.
            for ii = 1 : obj.imagesPerEpoch
                img_index = obj.sequence(current_index + ii);
                s = strsplit(obj.fullImagePaths{img_index}, filesep);
                obj.image_name = s{end};
%                 obj.image_name = obj.imagePaths{img_index, 1};
                % Load the image.
                myImage = imread(obj.fullImagePaths{img_index});
%                 myImage = imread(fullfile(obj.directory, obj.image_name));
                obj.imageMatrix{ii} = uint8(myImage);
                folderName = [folderName, s{end-1}]; %#ok<AGROW>
                imageName = [imageName, obj.image_name]; %#ok<AGROW>
                if ii < obj.imagesPerEpoch
                    folderName = [folderName, ',']; %#ok<AGROW>
                    imageName = [imageName, ',']; %#ok<AGROW>
                end
            end
            
            % Get the magnification factor to retain aspect ratio.
            obj.magnificationFactor = ceil( max(obj.canvasSize(2)/size(obj.imageMatrix{1},1),obj.canvasSize(1)/size(obj.imageMatrix{1},2)) );
            
            % Create the background image.
            obj.backgroundImage = ones(size(myImage))*obj.backgroundIntensity;
            obj.backgroundImage = uint8(obj.backgroundImage*255);
            
            epoch.addParameter('folder', folderName);
            epoch.addParameter('imageName', imageName);
%             epoch.addParameter('folder', obj.directory);
            epoch.addParameter('magnificationFactor', obj.magnificationFactor);
            epoch.addParameter('flashFrames', obj.flashFrames);
            epoch.addParameter('gapFrames', obj.gapFrames);
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
