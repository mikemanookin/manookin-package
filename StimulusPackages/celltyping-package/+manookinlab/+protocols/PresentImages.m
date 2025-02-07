% Loads and presents image files.
classdef PresentImages < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp % Output amplifier
        preTime     = 250 % Pre time in ms
        flashTime   = 100 % Time to flash each image in ms
        gapTime     = 400 % Gap between images in ms
        tailTime    = 250 % Tail time in ms
        imagesPerEpoch = 10 % Number of images to flash on each epoch
        fileFolder = 'flashImages'; % Folder in path containing images.
        backgroundIntensity = 0.5; % 0 - 1 (corresponds to image intensities in folder)
        randomize = true; % whether to randomize movies shown
        onlineAnalysis = 'none'
        numberOfAverages = uint16(5) % number of epochs to queue
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
        seed
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
            
            % General directory
            try
                image_dir = obj.rig.getDevice('Stage').getConfigurationSetting('local_image_directory');
                if isempty(image_dir)
                    image_dir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\';
                end
            catch
                image_dir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\';
            end
            obj.directory = strcat(image_dir, obj.fileFolder); % General folder
            D = dir(obj.directory);
            
            obj.imagePaths = cell(size(D,1),1);
            for a = 1:length(D)
                if sum(strfind(D(a).name,'.png')) > 0
                    obj.imagePaths{a,1} = D(a).name;
                end
            end
            obj.imagePaths = obj.imagePaths(~cellfun(@isempty, obj.imagePaths(:,1)), :);
            
            num_reps = ceil(double(obj.numberOfAverages)/size(obj.imagePaths,1)*obj.imagesPerEpoch);
            
            if obj.randomize
                obj.sequence = zeros(1,obj.numberOfAverages*obj.imagesPerEpoch);
%                 seq = (1:size(obj.imagePaths,1));
                for ii = 1 : num_reps
                    seq = randperm(size(obj.imagePaths,1));
                    obj.sequence((ii-1)*length(seq)+(1:length(seq))) = seq;
                end
                obj.sequence = obj.sequence(1:obj.numberOfAverages*obj.imagesPerEpoch);
            else
                obj.sequence = (1:size(obj.imagePaths,1))' * ones(1,num_reps);
                obj.sequence = obj.sequence(:);
            end
            
        end

        
        function p = createPresentation(obj)
            
            % Stage presets
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();     
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            
            p.setBackgroundColor(obj.backgroundIntensity)   % Set background intensity
            
            % Prep to display image
            scene = stage.builtin.stimuli.Image(obj.imageMatrix{1});
            scene.size = [canvasSize(1),canvasSize(2)];
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
            imgValue = stage.builtin.controllers.PropertyController(scene, ...
                'imageMatrix', @(state)setImage(obj, state.time - obj.preTime*1e-3));
            % Add the controller.
            p.addController(imgValue);

            function s = setImage(obj, time)
                img_index = floor( time / ((obj.flashTime+obj.gapTime)*1e-3) ) + 1;
                if img_index < 1 || img_index > obj.imagesPerEpoch
                    s = obj.backgroundImage;
                elseif (time >= ((obj.flashTime+obj.gapTime)*1e-3)*(img_index-1)) && (time <= (((obj.flashTime+obj.gapTime)*1e-3)*(img_index-1)+obj.flashTime*1e-3))
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
            imageName = ''; % Concatenate the image names separated by a comma.
            for ii = 1 : obj.imagesPerEpoch
                img_name = obj.sequence(current_index + ii);
                obj.image_name = obj.imagePaths{img_name, 1};
                % Load the image.
                specificImage = imread(fullfile(obj.directory, obj.image_name));
                obj.imageMatrix{ii} = specificImage;
                imageName = [imageName,obj.image_name]; %#ok<AGROW>
                if ii < obj.imagesPerEpoch
                    imageName = [imageName,',']; %#ok<AGROW>
                end
            end
            
            % Create the background image.
            obj.backgroundImage = ones(size(specificImage))*obj.backgroundIntensity;
            obj.backgroundImage = uint8(obj.backgroundImage*255);
            
            disp(imageName)
            
            epoch.addParameter('imageName', imageName);
            epoch.addParameter('folder', obj.directory);
            if obj.randomize
                epoch.addParameter('seed', obj.seed);
            end
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
