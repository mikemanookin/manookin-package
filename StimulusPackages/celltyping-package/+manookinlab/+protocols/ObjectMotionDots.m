classdef ObjectMotionDots < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Texture leading duration (ms)
        tailTime = 250                  % Texture trailing duration (ms)
        waitTime = 2000                 % Time texture is presented before moving (ms)
        moveTime = 2000                 % Move duration (ms)
        spaceConstants = 100:100:500    % Correlation constants (um)
        radius = 10                     % Dot radius (microns)
        dotDensity = 200                % Number of dots per square mm.
        contrast = 1.0                  % Texture contrast (0-1)
        driftSpeed = 1000               % Texture drift speed (um/sec)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Type of online analysis
        numberOfAverages = uint16(24)   % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        seed
        radiusPix
        spaceConstantsPix
        spaceConstantPix
        numDots
        motionPerFrame
        positionMatrix
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            if ~strcmp(obj.onlineAnalysis, 'none')
                colors = [0 0 0; 0.8 0 0; 0 0.5 0; 0 0.7 0.2; 0 0.2 1];
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',colors,...
                    'groupBy',{'spaceConstant'});
            end
            
            obj.motionPerFrame = obj.rig.getDevice('Stage').um2pix(obj.driftSpeed) / 60;
            obj.radiusPix = obj.rig.getDevice('Stage').um2pix(obj.radius);
            obj.spaceConstantsPix = obj.rig.getDevice('Stage').um2pix(obj.spaceConstants);
            
            % Get the canvas size in square mm.
            cSize = obj.canvasSize/obj.rig.getDevice('Stage').um2pix(1) * 1e-3;
            % Get the number of dots.
            obj.numDots = ceil(obj.dotDensity * (cSize(1)*cSize(2)));
        end
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            dotIntensity = obj.contrast;
            
            % Generate the dots.
            for k = 1 : obj.numDots
                spot = stage.builtin.stimuli.Ellipse();
                spot.radiusX = obj.radiusPix;
                spot.radiusY = obj.radiusPix;
                spot.position = obj.canvasSize/2;
                spot.color = dotIntensity;
                
                % Add the stimulus to the presentation.
                p.addStimulus(spot);
                
                % Make the dot visible only during the stimulus period.
                dotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(dotVisible);
                
                positionController = stage.builtin.controllers.PropertyController(spot, 'position',...
                    @(state)objectPosition(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3, k));
                p.addController(positionController);
            end
            
             
            %--------------------------------------------------------------
            % Control the texture position.
            function p = objectPosition(obj, time, whichDot)
                if time > 0 && time <= obj.moveTime*1e-3
                    whichFrame = floor(time * obj.frameRate) + 1;
                    p = squeeze(obj.positionMatrix(whichFrame,whichDot,:));
                else
                    p = squeeze(obj.positionMatrix(1,whichDot,:));
                end
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current space constant.
            obj.spaceConstantPix = obj.spaceConstantsPix(mod(obj.numEpochsCompleted,length(obj.spaceConstantsPix))+1);
            spaceConstant = obj.spaceConstants(mod(obj.numEpochsCompleted,length(obj.spaceConstants))+1);
            epoch.addParameter('spaceConstant',spaceConstant);
            
            % Deal with the seed.
            obj.seed = RandStream.shuffleSeed;
            epoch.addParameter('seed', obj.seed);
            
            % Calculate the stimulus frames.
            stimFrames = ceil(obj.moveTime * 1e-3 * obj.frameRate) + 30;
            
            % Get the position matrix.
            obj.positionMatrix = manookinlab.util.getXYDotTrajectories(stimFrames,obj.motionPerFrame,obj.spaceConstantPix,obj.numDots,obj.canvasSize,obj.seed);
            
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.waitTime + obj.moveTime;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end 