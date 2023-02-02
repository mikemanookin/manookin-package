classdef FlashedGratingDiscrimination < edu.washington.riekelab.protocols.RiekeLabStageProtocol

    properties
        preTime = 200 % ms
        flashTime = 200 % ms
        tailTime = 200 % ms
        
        apertureDiameter = 2000 % um

        gratingContrast = 0.75; %as a fraction of background intensity
        testContrast = [-0.2 -0.1 -0.05 0.05 0.1 0.2]
        barWidth = 50 % um
        backgroundIntensity = 0.25; %0-1
        randomizeOrder = false;
       
        onlineAnalysis = 'none'
        amp % Output amplifier
        WeberConstant = 2000;
        maxIntensity = 12000;
        numberOfAverages = uint16(90) % 6 x noContrasts x noRepeats
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        testContrastSequence
        currentTestContrast
        currentGrateContrast
        gratePolarity
        grateMatrix
        testType
    end
    
    properties (Dependent)
        stimTime
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'groupBy',{'currentTestContrast'});
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            
            % Create bar width sequence.
            obj.testContrastSequence = obj.testContrast;

        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.flashTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
                              
            index = mod(obj.numEpochsCompleted, 2*length(obj.testContrastSequence));
            % Randomize the bar width sequence order at the beginning of each sequence.
            if index == 0 && obj.randomizeOrder
                obj.testContrastSequence = randsample(obj.testContrastSequence, length(obj.testContrastSequence));
            end
            obj.currentTestContrast = obj.testContrastSequence(floor(index/2)+1);
            if (rem(index, 2) == 0)
                obj.testType = 'orig';
            else
                obj.testType = 'modified';
            end
            
            if (rem(floor(obj.numEpochsCompleted / (2*length(obj.testContrastSequence))), 3) == 0)
                obj.gratePolarity = 1;
                obj.currentGrateContrast = obj.gratingContrast;
            end
            if (rem(floor(obj.numEpochsCompleted / (2*length(obj.testContrastSequence))), 3) == 1)
                obj.gratePolarity = -1;
                obj.currentGrateContrast = obj.gratingContrast;
            end
            if (rem(floor(obj.numEpochsCompleted / (2*length(obj.testContrastSequence))), 3) == 2)
                obj.gratePolarity = 1;
                obj.currentGrateContrast = 0;
            end
            
            % bar greater than 1/2 aperture size -> just split field grating.
            % Allows grating texture to be the size of the aperture and the
            % resulting stimulus is the same...
            if (obj.barWidth > obj.apertureDiameter/2);
                obj.barWidth = obj.apertureDiameter/2;
            end
            epoch.addParameter('currentTestContrast', obj.currentTestContrast);
            epoch.addParameter('currentGrateContrast', obj.currentGrateContrast);
            epoch.addParameter('gratePolarity', obj.gratePolarity);
            epoch.addParameter('testType', obj.testType);     
            
        end
        
        function p = createPresentation(obj)            
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.flashTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            %convert from microns to pixels...
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            grateBarSizePix = obj.rig.getDevice('Stage').um2pix(obj.barWidth);
            
            grateSize = canvasSize(2);
            grateX = sign(obj.gratePolarity * sin(2*pi*(-grateSize/2:grateSize/2-1) / grateBarSizePix));
            grateMatrix = repmat(grateX, canvasSize(1), 1);
            obj.grateMatrix = obj.backgroundIntensity + grateMatrix * obj.backgroundIntensity * obj.currentGrateContrast;
            board = stage.builtin.stimuli.Image(uint8(255*obj.grateMatrix));
            board.size = canvasSize;
            board.position = canvasSize/2;
            board.setMinFunction(GL.NEAREST); %don't interpolate to scale up board
            board.setMagFunction(GL.NEAREST);
            p.addStimulus(board);
                                                    
            if (obj.apertureDiameter > 0) %% Create aperture
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2;
                aperture.color = obj.backgroundIntensity;
                aperture.size = [max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createCircularAperture(apertureDiameterPix/max(canvasSize), 1024); %circular aperture
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
            
            preFrames = round(60 * (obj.preTime/1e3));
            flashFrames = round(60 * (obj.flashTime/1e3));
            imageController = stage.builtin.controllers.PropertyController(board, 'imageMatrix',...
                @(state)getNewImage(obj, state.frame, preFrames, flashFrames));
            p.addController(imageController); %add the controller

            function i = getNewImage(obj, frame, preFrames, flashFrames)
                persistent boardMatrix;
                if (frame == 0)
                    boardMatrix = obj.grateMatrix; 
                end
                if (frame == preFrames)
                    testMatrix = ones(size(obj.grateMatrix)) * obj.currentTestContrast * obj.backgroundIntensity;
                    if (strcmp(obj.testType, 'modified'))
                        coneGain = 1 ./ (1 + ((double(obj.grateMatrix)) * obj.maxIntensity) / obj.WeberConstant);
                        coneGain = coneGain / mean(coneGain(:));
                        testMatrix = testMatrix ./ coneGain;
                    end
                    boardMatrix = obj.grateMatrix + testMatrix;
                end
                if (frame == preFrames + flashFrames)
                    boardMatrix = obj.grateMatrix; 
                end
                if (max(boardMatrix(:))> 1 | min(boardMatrix < 0))
                    display(['out of range' num2str(rand(1,1))]);
                end
                i = uint8(255*boardMatrix);
            end

        end
        
        function stimTime = getStimTime(obj)
            stimTime = (obj.preTime + obj.flashTime + obj.tailTime) * 1e-3;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end

    end
    
end