classdef ObjectMotionDots < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Texture leading duration (ms)
        tailTime = 250                  % Texture trailing duration (ms)
        waitTime = 0                    % Time texture is presented before moving (ms)
        moveTime = 5000                 % Move duration (ms)
        spaceConstants = [50,100:100:500,750,1000]    % Correlation constants (um)
        correlationFrames = 12           % Time course between reset of correlations
        radius = 40                     % Dot radius (microns)
        dotDensity = 200                % Number of dots per square mm.
        contrast = 1.0                  % Texture contrast (0-1)
        splitContrasts = true           % Half of dots will be opposite polarity.
        motionStd = 1000                % Standard deviation of motion speed (um/sec)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Type of online analysis
        numberOfAverages = uint16(64)   % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        spaceConstantsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        seed
        radiusPix
        spaceConstantsPix
        spaceConstantPix
        numDots
        motionPerFrame
        imageMatrix
        numXChecks
        numYChecks
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            colors = [0 0 0; 0.8 0 0; 0 0.5 0; 0 0.7 0.2; 0 0.2 1];
            nReps = ceil(length(obj.spaceConstants)/size(colors,1));
            if nReps > 1
                colors = repmat(colors,[nReps,1]);
            end
            colors = colors(1:length(obj.spaceConstants),:);
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.IntegratedResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'preTime',obj.preTime,...
                    'stimTime',obj.stimTime,...
                    'groupBy',{'spaceConstant'});
            end
            
            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                if ~strcmp(obj.onlineAnalysis, 'none')
                    obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                        obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                        'sweepColor',colors,...
                        'groupBy',{'spaceConstant'});
                end
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
                if ~strcmp(obj.onlineAnalysis, 'none')
                    obj.showFigure('manookinlab.figures.DualMeanResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2),...
                        'recordingType',obj.onlineAnalysis,...
                        'sweepColor1',colors,...
                        'groupBy1',{'spaceConstant'},...
                        'sweepColor2',colors,...
                        'groupBy2',{'spaceConstant'});
                end
            end
            
            obj.radiusPix = obj.rig.getDevice('Stage').um2pix(obj.radius);
            obj.motionPerFrame = obj.rig.getDevice('Stage').um2pix(obj.motionStd) / 60 / obj.radiusPix;
            obj.spaceConstantsPix = obj.rig.getDevice('Stage').um2pix(obj.spaceConstants) / obj.radiusPix;
            
            obj.numXChecks = ceil(obj.canvasSize(1)/obj.radiusPix);
            obj.numYChecks = ceil(obj.canvasSize(2)/obj.radiusPix);
            
            % Get the canvas size in square mm.
            cSize = obj.canvasSize * (1e6/obj.rig.getDevice('Stage').um2pix(1e6)) * 1e-3;
            % Get the number of dots.
            obj.numDots = ceil(obj.dotDensity * (cSize(1)*cSize(2)));
        end
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            
            checkerboard = stage.builtin.stimuli.Image(obj.imageMatrix(:,:,1));
            checkerboard.position = obj.canvasSize / 2;
            checkerboard.size = [obj.numXChecks obj.numYChecks] * obj.radiusPix;

            % Set the minifying and magnifying functions to form discrete
            % stixels.
            checkerboard.setMinFunction(GL.NEAREST);
            checkerboard.setMagFunction(GL.NEAREST);
            
            % Add the stimulus to the presentation.
            p.addStimulus(checkerboard);
            
            gridVisible = stage.builtin.controllers.PropertyController(checkerboard, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(gridVisible);
            
            % Calculate preFrames and stimFrames
            preF = floor(obj.preTime/1000 * obj.frameRate);
            stimF = floor(obj.stimTime/1000 * obj.frameRate);

            imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                @(state)setStixels(obj, state.frame - preF, stimF));
            p.addController(imgController);

            function s = setStixels(obj, frame, stimFrames)
                if frame > 0 && frame <= stimFrames
                    s = squeeze(obj.imageMatrix(:,:,frame));
                else
                    s = squeeze(obj.imageMatrix(:,:,1));
                end
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Remove the Amp responses if it's an MEA rig.
            if obj.isMeaRig && ~strcmp(obj.onlineAnalysis, 'none')
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
            
            % Get the current space constant.
            obj.spaceConstantPix = obj.spaceConstantsPix(mod(obj.numEpochsCompleted,length(obj.spaceConstantsPix))+1);
            spaceConstant = obj.spaceConstants(mod(obj.numEpochsCompleted,length(obj.spaceConstants))+1);
            epoch.addParameter('spaceConstant',spaceConstant);
            
            % Deal with the seed.
            obj.seed = RandStream.shuffleSeed;
            epoch.addParameter('seed', obj.seed);
            
            % Calculate the stimulus frames.
            stimFrames = ceil(obj.moveTime * 1e-3 * obj.frameRate) + 30;
            epoch.addParameter('stimFrames', stimFrames);
            
            % Get the position matrix.
            obj.imageMatrix = manookinlab.util.getXYDotTrajectories(stimFrames,obj.motionPerFrame,obj.spaceConstantPix,obj.numDots,[obj.numYChecks,obj.numXChecks],obj.seed,obj.correlationFrames,obj.splitContrasts);
            % Multiply by the contrast and convert to uint8.
            obj.imageMatrix = obj.contrast * obj.imageMatrix;
            obj.imageMatrix = uint8(255*(obj.backgroundIntensity*obj.imageMatrix + obj.backgroundIntensity));
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.waitTime + obj.moveTime;
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