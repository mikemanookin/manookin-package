classdef FlashedGratePlusNoise < edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol

    properties
        preTime = 200 % ms
        stimTime = 200 % ms
        tailTime = 200 % ms
        maskDiameter = 0;
        apertureDiameter = 200 % um
        grateBarSize = 60;
        persistentGrate = false % false = grating flashed with noise
        noiseFilterSD = 2 % pixels
        noiseContrast = 1;
        numNoiseRepeats = 20;
        linearizeCones = false;
        WeberConstant = 2000;
        maxIntensity = 25000;
        numberOfAverages = uint16(180) % number of epochs to queue
    end
    
    properties (Hidden)
        %saved out to each epoch...
        stimulusTag
        imagePatchIndex
        currentPatchLocation
        temporalMask
        noiseSeed
        noiseStream
        currentNoiseContrast
        gratePolarity
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol(obj);

            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
            end
            
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis);
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
        
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) * obj.numNoiseRepeats / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            if numel(obj.rig.getDeviceNames('Amp')) >= 2
                epoch.addResponse(obj.rig.getDevice(obj.amp2));
            end
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            grateBarSizePix = obj.rig.getDevice('Stage').um2pix(obj.grateBarSize) / 3.3; % VH pixels
                    
            %pull patch location:
            obj.imagePatchIndex = mod(floor(obj.numEpochsCompleted),3) + 1;
            
            if (obj.imagePatchIndex <= obj.noPatches)
                obj.currentPatchLocation(1) = obj.patchLocations(1,obj.imagePatchIndex); %in VH pixels
                obj.currentPatchLocation(2) = obj.patchLocations(2,obj.imagePatchIndex);
            end
            
            obj.imagePatchMatrix = ...
                edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol.getImagePatchMatrix(...
                obj, obj.currentPatchLocation);
            
            if (obj.imagePatchIndex == 1)
                grateSize = size(obj.imagePatchMatrix, 2);
                obj.gratePolarity = 1;
                grateX = sign(sin(2*pi*(-grateSize/2:grateSize/2-1) / grateBarSizePix));
                grateMatrix = repmat(grateX, size(obj.imagePatchMatrix, 1), 1);
                obj.imagePatchMatrix = uint8(255 * (obj.backgroundIntensity + grateMatrix * obj.backgroundIntensity * 0.5));
            end
            if (obj.imagePatchIndex == 2)
                grateSize = size(obj.imagePatchMatrix, 2);
                obj.gratePolarity = -1;
                grateX = sign(-sin(2*pi*(-grateSize/2:grateSize/2-1) / grateBarSizePix));
                grateMatrix = repmat(grateX, size(obj.imagePatchMatrix, 1), 1);
                obj.imagePatchMatrix = uint8(255 * (obj.backgroundIntensity + grateMatrix * obj.backgroundIntensity * 0.5));
            end
            if (obj.imagePatchIndex == 3)
                obj.imagePatchMatrix(:) = uint8(obj.backgroundIntensity * 255);              
            end
            
            imageMatrixStixelSize = canvasSize(1) / size(obj.imagePatchMatrix, 1);
            maskDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.maskDiameter);
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            
            distanceMatrix = createDistanceMatrix(size(obj.imagePatchMatrix, 2)-1, size(obj.imagePatchMatrix, 1)-1, imageMatrixStixelSize);
            
            if (obj.maskDiameter > 0)
                Indices = find(distanceMatrix(:) < maskDiameterPix);
                obj.imagePatchMatrix(Indices) = uint8(obj.backgroundIntensity * 255);
            end
            
            if (obj.apertureDiameter > 0)
                Indices = find(distanceMatrix(:) > apertureDiameterPix);
                obj.imagePatchMatrix(Indices) = uint8(obj.backgroundIntensity * 255);              
            end
            
            obj.noiseSeed = RandStream.shuffleSeed;
            
            %at start of epoch, set random stream
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.noiseSeed);

            obj.currentNoiseContrast = obj.noiseContrast;
            
            if (obj.imagePatchIndex <= obj.noPatches)
                epoch.addParameter('imageType', 'patch');
            end
            if (obj.imagePatchIndex == obj.noPatches+1)
                epoch.addParameter('imageType', 'grate');
                epoch.addParameter('gratePolarity', obj.gratePolarity);
%                obj.currentNoiseContrast = 0;
            end
            if (obj.imagePatchIndex == obj.noPatches+2)
                epoch.addParameter('imageType', 'none');
            end
            epoch.addParameter('noiseSeed', obj.noiseSeed);
            epoch.addParameter('imagePatchIndex', obj.imagePatchIndex);
            epoch.addParameter('currentPatchLocation', obj.currentPatchLocation);
            epoch.addParameter('currentNoiseContrast', obj.currentNoiseContrast);
            
            function m = createDistanceMatrix(xsize, ysize, stixelSize)
                [xx, yy] = meshgrid(-xsize/2:1:xsize/2, -ysize/2:1:ysize/2);
                m = sqrt((xx*stixelSize).^2 + (yy*stixelSize).^2);
            end

        end
        
        function p = createPresentation(obj)            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * obj.numNoiseRepeats * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            imageMatrixStixelSize = canvasSize(1) / size(obj.imagePatchMatrix, 1);
            distanceMatrix = createDistanceMatrix(size(obj.imagePatchMatrix, 2)-1, size(obj.imagePatchMatrix, 1)-1, imageMatrixStixelSize);
            if (apertureDiameterPix > 0)
                Indices = find(distanceMatrix(:) > apertureDiameterPix);
            else
                Indices = nan;
            end
                       
            % Create image
            initMatrix = uint8(255.*(obj.backgroundIntensity .* ones(size(obj.imagePatchMatrix))));
            board = stage.builtin.stimuli.Image(initMatrix);
            board.size = canvasSize;
            board.position = canvasSize/2;
            board.setMinFunction(GL.NEAREST); %don't interpolate to scale up board
            board.setMagFunction(GL.NEAREST);
            p.addStimulus(board);
            preFrames = round(60 * (obj.preTime/1e3));
            flashDurFrames = round(60 * ((obj.preTime + obj.stimTime + obj.tailTime))/1e3);
            imageController = stage.builtin.controllers.PropertyController(board, 'imageMatrix',...
                @(state)getNewImage(obj, state.frame, preFrames, flashDurFrames, Indices));
            p.addController(imageController); %add the controller
                     
            function i = getNewImage(obj, frame, preFrames, flashDurFrames, Indices)
                persistent boardMatrix;
                curFrame = rem(frame, flashDurFrames);
                if curFrame == preFrames
                    noiseMatrix = imgaussfilt(obj.noiseStream.randn(size(obj.imagePatchMatrix)), obj.noiseFilterSD);
                    noiseMatrix = noiseMatrix / std(noiseMatrix(:));
                    if (obj.linearizeCones)
                        coneGain = 1 ./ (1 + ((double(obj.imagePatchMatrix)) * obj.maxIntensity/255) / obj.WeberConstant);
                        noiseMatrix = noiseMatrix ./ coneGain;
                    end
                    boardMatrix = obj.imagePatchMatrix - 255*obj.backgroundIntensity + uint8(255 * noiseMatrix * obj.backgroundIntensity * obj.currentNoiseContrast + 255*obj.backgroundIntensity);
                    if (~isnan(Indices))
                        boardMatrix(Indices) = uint8(obj.backgroundIntensity * 255);
                    end
                end
                if curFrame == 0
                    if (obj.persistentGrate)
                        boardMatrix = obj.imagePatchMatrix;
                    else
                        boardMatrix = 255 * obj.backgroundIntensity .* ones(size(obj.imagePatchMatrix));
                    end
                end
                if curFrame == (flashDurFrames-1)
                    if (obj.persistentGrate)
                        boardMatrix = obj.imagePatchMatrix;
                    else
                        boardMatrix = 255 * obj.backgroundIntensity .* ones(size(obj.imagePatchMatrix));
                    end
                end
                if (max(boardMatrix(:)) == 255 | min(boardMatrix(:) == 0))
                    display(['out of range' num2str(rand(1,1))]);
                end
                i = uint8(boardMatrix);
            end
            
            function m = createDistanceMatrix(xsize, ysize, stixelSize)
                [xx, yy] = meshgrid(-xsize/2:1:xsize/2, -ysize/2:1:ysize/2);
                m = sqrt((xx*stixelSize).^2 + (yy*stixelSize).^2);
            end
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
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

    end
    
end