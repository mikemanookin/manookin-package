classdef MovingGabor < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    % todo:
    %   - cone iso and color
    
    properties
        stimTime = 660 % ms
        spatialPeriod = 300             % period of spatial grating (um)
        stepSize = 5                    % step size for random walk (um)
        gaborStanDev = 80               % standard deviation of Gaussian envelope (um)
        contrasts = [0.1 0.2 0.4]       % Grating contrasts [0, 1]
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        numberOfAverages = uint16(5)    % Number of epochs at each contrast
        amp                             % Output amplifier
        psth = false;                   % Toggle psth in mean response figure
    end
    
    properties (Hidden)
        ampType
        currentContrast
        currentPosition
        noiseSeed
        noiseStream
        movementIndex
        preTime
        tailTime
        stepSizePix
    end
    
    properties (Hidden, Transient)
        analysisFigure
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            if length(obj.contrasts) > 1
                colors = edu.washington.riekelab.turner.utils.pmkmp(length(obj.contrasts),'CubicYF');
            else
                colors = [0 0 0];
            end
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.figures.MeanResponseFigure', obj.rig.getDevice(obj.amp), ...
                    'groupBy', {'currentContrast'},'sweepColor',colors,'psth', obj.psth);
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            
            obj.preTime = 0;
            obj.tailTime = 0;
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            
            device = obj.rig.getDevice(obj.amp);
            duration = obj.stimTime * 1e-3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            obj.currentPosition = canvasSize/2;
            obj.movementIndex = mod(obj.numEpochsCompleted,4)+1;
            contrastIndex = mod(floor(obj.numEpochsCompleted/4), length(obj.contrasts))+1;
            
            obj.noiseSeed = RandStream.shuffleSeed;         
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.noiseSeed);

            obj.currentContrast = obj.contrasts(contrastIndex);
            epoch.addParameter('currentContrast', obj.currentContrast);
            epoch.addParameter('seed',  obj.noiseSeed);
                        
        end
        
        function p = createPresentation(obj)

            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            spatialPeriodPix = obj.rig.getDevice('Stage').um2pix(obj.spatialPeriod);
            gaborStanDevPix = obj.rig.getDevice('Stage').um2pix(obj.gaborStanDev);
            obj.stepSizePix = obj.rig.getDevice('Stage').um2pix(obj.stepSize);
            
            p = stage.core.Presentation(obj.stimTime * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create the grating stimulus.
            grating = stage.builtin.stimuli.Grating();
            grating.position = canvasSize / 2;
            grating.size = [gaborStanDevPix*4, gaborStanDevPix*4];
            grating.spatialFreq = 1/spatialPeriodPix; 
            grating.color = 2*obj.backgroundIntensity;
            grating.phase = 0;
            
            % Create a controller to change the grating's phase property as a function of time. 
            gaborPositionController = stage.builtin.controllers.PropertyController(grating, 'position', ...
                @(state)getGaborPosition(obj, state.time));
            gaborContrastController = stage.builtin.controllers.PropertyController(grating, 'contrast',...
                        @(state)getGaborContrast(obj, state.time));

            % Add the stimulus and controller.
            p.addStimulus(grating);
            p.addController(gaborPositionController);
            p.addController(gaborContrastController);

            % Assign a gaussian envelope mask to the grating.
            mask = stage.core.Mask.createGaussianEnvelope(gaborStanDevPix*2);
            grating.setMask(mask);

            function p = getGaborPosition(obj, time)
                if (obj.movementIndex == 1)
                    obj.currentPosition(1) = obj.currentPosition(1) + round(obj.noiseStream.randn() * obj.stepSizePix);
                end
                if (obj.movementIndex == 2)
                    obj.currentPosition(2) = obj.currentPosition(2) + round(obj.noiseStream.randn() * obj.stepSizePix);
                end
                if (obj.movementIndex == 3)
                    obj.currentPosition(1) = obj.currentPosition(1) + round(obj.noiseStream.randn() * obj.stepSizePix);
                    obj.currentPosition(2) = obj.currentPosition(2) + round(obj.noiseStream.randn() * obj.stepSizePix);
                end
                p = obj.currentPosition;
            end
            
            function c = getGaborContrast(obj, time)
                c = obj.currentContrast;
                if (time < obj.stimTime*1e-3/4)
                    c = obj.currentContrast * time/(obj.stimTime*1e-3/4);
                end
                if (time > obj.stimTime*1e-3*3/4)
                    c = obj.currentContrast * (obj.stimTime*1e-3 - time)/(obj.stimTime*1e-3/4);
                end
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