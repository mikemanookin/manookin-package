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
        numberOfAverages = uint16(90) 
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        testContrastSequence
        currentTestContrast
        currentGrateContrast
        gratePolarity
        testPolarity
        grateMatrix
        testType
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
            duration = (obj.preTime + obj.flashTime + obj.tailTime) * 1e-3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
                              
            index = mod(obj.numEpochsCompleted, 9*length(obj.testContrastSequence));
            % Randomize the bar width sequence order at the beginning of each sequence.
            if index == 0 && obj.randomizeOrder
                obj.testContrastSequence = randsample(obj.testContrastSequence, length(obj.testContrastSequence));
            end
            obj.currentTestContrast = obj.testContrastSequence(floor(index/9)+1);
            
            stimIndex = rem(obj.numEpochsCompleted, 9);
            
            switch stimIndex
                case 0
                    obj.gratePolarity = 1;
                    obj.testPolarity = 0;
                    obj.currentGrateContrast = obj.gratingContrast;
                case 1
                    obj.gratePolarity = 1;
                    obj.testPolarity = 1;
                    obj.currentGrateContrast = obj.gratingContrast;
                case 2
                    obj.gratePolarity = 1;
                    obj.testPolarity = -1;
                    obj.currentGrateContrast = obj.gratingContrast;
                case 3
                    obj.gratePolarity = -1;
                    obj.testPolarity = 0;
                    obj.currentGrateContrast = obj.gratingContrast;
                case 4
                    obj.gratePolarity = -1;
                    obj.testPolarity = 1;
                    obj.currentGrateContrast = obj.gratingContrast;
                case 5
                    obj.gratePolarity = -1;
                    obj.testPolarity = -1;
                    obj.currentGrateContrast = obj.gratingContrast;
                case 6
                    obj.gratePolarity = 1;
                    obj.testPolarity = 0;
                    obj.currentGrateContrast = 0; % no grate
                case 7
                    obj.gratePolarity = 1;
                    obj.testPolarity = 1;
                    obj.currentGrateContrast = 0; % no grate
                case 8
                    obj.gratePolarity = 1;
                    obj.testPolarity = -1;
                    obj.currentGrateContrast = 0; % no grate
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
            epoch.addParameter('testPolarity', obj.testPolarity);     
            fprintf(1, 'done prepare\n');
            
        end
        
        function p = createPresentation(obj)            
                        fprintf(1, 'start  create 0\n');
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.flashTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            %convert from microns to pixels...
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            grateBarSizePix = obj.rig.getDevice('Stage').um2pix(obj.barWidth);

                        fprintf(1, 'mid  create 0\n');

            grateSize = canvasSize(2);
            grateX = sign(obj.gratePolarity * sin(2*pi*(-grateSize/2:grateSize/2-1) / grateBarSizePix));
            obj.grateMatrix = repmat(grateX, canvasSize(1), 1);
            board = stage.builtin.stimuli.Image(uint8(255*obj.grateMatrix));
            board.size = canvasSize;
            board.position = canvasSize/2;
            board.setMinFunction(GL.NEAREST); %don't interpolate to scale up board
            board.setMagFunction(GL.NEAREST);
            p.addStimulus(board);
                        fprintf(1, 'mid create\n');
                        
            if (obj.apertureDiameter > 0) %% Create aperture
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2;
                aperture.color = obj.backgroundIntensity;
                aperture.size = [max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createCircularAperture(apertureDiameterPix/max(canvasSize), 1024); %circular aperture
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
                            fprintf(1, 'mid create 2\n');
        
            preFrames = round(60 * (obj.preTime/1e3));
            flashFrames = round(60 * (obj.flashTime/1e3));
            imageController = stage.builtin.controllers.PropertyController(board, 'imageMatrix',...
                @(state)getNewImage(obj, state.frame, preFrames, flashFrames));
            p.addController(imageController); %add the controller

            fprintf(1, 'done create\n');
            function i = getNewImage(obj, frame, preFrames, flashFrames)
                persistent boardMatrix;
                if (frame == 0)
                    boardMatrix = obj.backgroundIntensity + obj.grateMatrix * obj.backgroundIntensity * obj.currentGrateContrast; 
                end
                if (frame == preFrames)
                    testMatrix = ones(size(obj.grateMatrix)) * obj.currentTestContrast * obj.backgroundIntensity;
                    if (obj.testPolarity ~= 0)
                        RFWeights = (obj.backgroundIntensity + obj.grateMatrix * obj.backgroundIntensity * obj.gratingContrast) / obj.backgroundIntensity;
                        if (obj.testPolarity == 1)
                            testMatrix = testMatrix .* RFWeights;
                        else
                            testMatrix = testMatrix ./ RFWeights;
                        end
                    end
                    boardMatrix = obj.backgroundIntensity + obj.grateMatrix * obj.backgroundIntensity * obj.currentGrateContrast + testMatrix;
                end
                if (frame == preFrames + flashFrames)
                    boardMatrix = obj.backgroundIntensity + obj.grateMatrix * obj.backgroundIntensity * obj.currentGrateContrast;
                end
                if (max(boardMatrix(:))> 1 | min(boardMatrix < 0))
                    display(['out of range' num2str(rand(1,1))]);
                end
                i = uint8(255*boardMatrix);
            end

        end
                
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end

        function stimTime = get.stimTime(obj)
            stimTime = (obj.preTime + obj.flashTime + obj.tailTime);
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