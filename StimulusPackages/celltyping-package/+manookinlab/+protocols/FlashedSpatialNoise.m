classdef FlashedSpatialNoise < edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol

    properties
        preTime = 200 % ms
        flashTime = 200 % ms
        tailTime = 200 % ms
        occluderWidth = [0 50 100 200];
        noiseFilterSD = 2 % pixels
        noiseContrast = 1;
        numberOfAverages = uint16(180) % number of epochs to queue
    end
    
    properties (Hidden)
        %saved out to each epoch...
        currentPatchLocation
        temporalMask
        noiseSeed
        noiseStream
        currentOccluderWidth
        stimType
        stimTime
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
            duration = (obj.preTime + obj.flashTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            if numel(obj.rig.getDeviceNames('Amp')) >= 2
                epoch.addResponse(obj.rig.getDevice(obj.amp2));
            end
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
                                
            %pull patch location:
            obj.currentPatchLocation(1) = obj.patchLocations(1,1); %in VH pixels
            obj.currentPatchLocation(2) = obj.patchLocations(2,1);
            
            obj.imagePatchMatrix = ...
                edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol.getImagePatchMatrix(...
                obj, obj.currentPatchLocation);
            
            obj.imagePatchMatrix(:) = uint8(obj.backgroundIntensity * 255);
            
            index = mod(obj.numEpochsCompleted, length(obj.occluderWidth)*2);
            obj.currentOccluderWidth = obj.occluderWidth(floor(index/2)+1);
            if (rem(index, 2) == 1)
                obj.stimType = 'occluded';
            else
                obj.stimType = 'front';
            end
            
            obj.noiseSeed = RandStream.shuffleSeed;
            
            %at start of epoch, set random stream
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.noiseSeed);

            epoch.addParameter('noiseSeed', obj.noiseSeed);
            epoch.addParameter('currentOccluderWidth', obj.currentOccluderWidth);
            epoch.addParameter('stimType', obj.stimType);
                       
        end
        
        function p = createPresentation(obj)            
            p = stage.core.Presentation((obj.preTime + obj.flashTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            occluderWidthPix = obj.rig.getDevice('Stage').um2pix(obj.currentOccluderWidth)/2;
            imageMatrixStixelSize = canvasSize(1) / size(obj.imagePatchMatrix, 1);
            occluderWidthStixel = round(occluderWidthPix / imageMatrixStixelSize);
         
            % Create image
            noiseMatrix = imgaussfilt(obj.noiseStream.randn(size(obj.imagePatchMatrix)), obj.noiseFilterSD);
            noiseMatrix = noiseMatrix / std(noiseMatrix(:));
            if (obj.currentOccluderWidth > 0)
                if (strcmp(obj.stimType, 'occluded') == 1);
                    noiseMatrix(:, size(noiseMatrix, 2)/2-occluderWidthStixel:size(noiseMatrix, 2)/2+occluderWidthStixel) = 0;
                else
                    noiseMatrix(:, 1:size(noiseMatrix, 2)/2-occluderWidthStixel) = 0;
                    noiseMatrix(:, size(noiseMatrix, 2)/2+occluderWidthStixel: size(noiseMatrix, 2)) = 0;
                end
            end
            
            board = stage.builtin.stimuli.Image(uint8(255 * noiseMatrix * obj.backgroundIntensity * obj.noiseContrast + ...
                255*obj.backgroundIntensity));
            board.size = canvasSize;
            board.position = canvasSize/2;
            board.setMinFunction(GL.NEAREST); %don't interpolate to scale up board
            board.setMagFunction(GL.NEAREST);
            p.addStimulus(board);

            imageController = stage.builtin.controllers.PropertyController(board, 'visible', ...
                    @(state)state.time >= (obj.preTime * 1e-3) && state.time < (obj.preTime + obj.flashTime) * 1e-3);
            p.addController(imageController);
                        
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end

        function stimTime = get.stimTime(obj)
            stimTime = obj.flashTime; %(obj.preTime + obj.flashTime + obj.tailTime);
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