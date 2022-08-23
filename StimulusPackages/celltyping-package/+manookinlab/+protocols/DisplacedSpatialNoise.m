classdef DisplacedSpatialNoise < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    properties
        preTime = 200 % ms
        flashTime = 200 % ms
        tailTime = 200 % ms
        
        edgeDisplacements = [0 25 50 75 100 150 200 300 500] % um
        noiseFilterSD = 2 % pixels
        noiseContrast = 1;
        backgroundIntensity = 0.5; 
        numNoiseRepeats = 10;
        numberOfAverages = uint16(180) % number of epochs to queue
        amp                             % Output amplifier
    end
    
    properties (Hidden)
        ampType
        initMatrix
        noiseSeed
        noiseStream
        currentEdgeDisplacement
    end
    
    properties (Dependent)
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
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);

            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
            end
            
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
        
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = ((obj.preTime + obj.flashTime + obj.tailTime) * obj.numNoiseRepeats) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
         
            if numel(obj.rig.getDeviceNames('Amp')) >= 2
                epoch.addResponse(obj.rig.getDevice(obj.amp2));
            end
            index = mod(obj.numEpochsCompleted, length(obj.edgeDisplacements)) + 1;
            obj.currentEdgeDisplacement = obj.edgeDisplacements(index);
            
            obj.noiseSeed = RandStream.shuffleSeed;
            
            %at start of epoch, set random stream
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.noiseSeed);

            epoch.addParameter('noiseSeed', obj.noiseSeed);
            epoch.addParameter('currentEdgeDisplacement', obj.currentEdgeDisplacement);
        end
        
        function p = createPresentation(obj)            
            p = stage.core.Presentation((obj.preTime + obj.flashTime + obj.tailTime) * obj.numNoiseRepeats * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            
            % Create image
            obj.initMatrix = uint8(255.*(obj.backgroundIntensity .* ones(canvasSize/4)));
            board = stage.builtin.stimuli.Image(obj.initMatrix);
            board.size = canvasSize;
            board.position = [obj.currentEdgeDisplacement canvasSize(2)/2];
            board.setMinFunction(GL.NEAREST); %don't interpolate to scale up board
            board.setMagFunction(GL.NEAREST);
            p.addStimulus(board);
            preFrames = round(60 * (obj.preTime/1e3));
            flashDurFrames = round(60 * ((obj.preTime + obj.flashTime + obj.tailTime))/1e3);
            imageController = stage.builtin.controllers.PropertyController(board, 'imageMatrix',...
                @(state)getNewImage(obj, state.frame, preFrames, flashDurFrames));
            p.addController(imageController); %add the controller

            function i = getNewImage(obj, frame, preFrames, flashDurFrames)
                persistent boardMatrix;
                curFrame = rem(frame, flashDurFrames);
                if curFrame == preFrames
                    noiseMatrix = imgaussfilt(obj.noiseStream.randn(size(obj.initMatrix)), obj.noiseFilterSD);
                    noiseMatrix = noiseMatrix / std(noiseMatrix(:));
                    boardMatrix = obj.initMatrix - 255*obj.backgroundIntensity + uint8(255 * noiseMatrix * obj.backgroundIntensity * obj.noiseContrast + 255*obj.backgroundIntensity);
                end
                if curFrame == 0
                    boardMatrix = 255 * obj.backgroundIntensity .* ones(size(obj.initMatrix));
                end
                if curFrame == (flashDurFrames-1)
                    boardMatrix = 255 * obj.backgroundIntensity .* ones(size(obj.initMatrix));
                end
                i = uint8(boardMatrix);
            end
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = (obj.preTime + obj.flashTime + obj.tailTime) * double(obj.numNoiseRepeats) - obj.preTime - obj.tailTime;
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