classdef AdaptNoiseColorSteps < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stim leading duration (ms)
        stimTime = 180000               % Stim duration (ms)
        tailTime = 250                  % Stim trailing 	 (ms)
        stepDuration = 2000             % Duration series (ms)
        stixelSizes = [60,90,60,90]     % Edge length of stixel (microns)
        gridSize = 30                   % Size of underling grid
        maxContrast = 0.5
        minContrast = 0.3
        frameDwells = uint16([2,2,1,1]) % Frame dwell.
        randsPerRep = -1                % Number of random seeds per repeat
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        noiseClass = 'gaussian_randn'   % Noise type (binary or Gaussian
        stimulusClass = 'full-field'    % Stimulus class
        chromaticClass = 'BY'           % Chromatic class
        backgroundClass = 'equal_catch' % Background class
        onlineAnalysis = 'none'         % Online analysis type.
        numberOfAverages = uint16(5)   % Number of epochs
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties (Hidden)
        ampType
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary','gaussian','gaussian_randn'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'full-field','spatial'})
        chromaticClassType = symphonyui.core.PropertyType('char','row',{'achromatic','RGB','BY'})
        backgroundClassType = symphonyui.core.PropertyType('char','row',{'chromatic','equal_catch','equal_luminance'})
        seed
        bkg
        noiseStream
        frameSeq
        contrasts
        durations
        stixelSize
        stepsPerStixel
        numXStixels
        numYStixels
        numXChecks
        numYChecks
        numFrames
        stixelSizePix
        stixelShiftPix
        imageMatrix
        positionStream
        bg_seq
        contrast_seq
        background_means
        backgroundColors = {'blue','gray','yellow'};
        frameDwell
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',[30 144 255]/255,...
                    'groupBy',{'frameRate'});
            end
            
            if obj.backgroundIntensity == 0
                obj.bkg = 0.5;
            else
                obj.bkg = obj.backgroundIntensity;
            end
            
            numSteps = ceil(obj.stimTime/obj.stepDuration);
            obj.durations = obj.stepDuration * ones(1, numSteps);
            if sum(obj.durations) > obj.stimTime
                obj.durations(end) = obj.durations(end) - (sum(obj.durations)-obj.stimTime);
            end
            
            % Get the number of frames.
            obj.numFrames = floor(obj.stimTime * 1e-3 * obj.frameRate)+15;
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.background_means);
            
            if strcmp(obj.stimulusClass, 'spatial')
                obj.imageMatrix = obj.background_means(1)*ones(obj.numYStixels,obj.numXStixels);
                checkerboard = stage.builtin.stimuli.Image(uint8(obj.imageMatrix*255));
                checkerboard.position = obj.canvasSize / 2;
                checkerboard.size = [obj.numXStixels, obj.numYStixels] * obj.stixelSizePix;

                % Set the minifying and magnifying functions to form discrete stixels.
                checkerboard.setMinFunction(GL.NEAREST);
                checkerboard.setMagFunction(GL.NEAREST);

                % Add the stimulus to the presentation.
                p.addStimulus(checkerboard);

                gridVisible = stage.builtin.controllers.PropertyController(checkerboard, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(gridVisible);

                % Calculate preFrames and stimFrames
                preF = floor(obj.preTime/1000 * 60);

                if ~strcmp(obj.chromaticClass,'achromatic') && isempty(strfind(obj.rig.getDevice('Stage').name, 'LightCrafter'))
                    if strcmp(obj.chromaticClass,'BY')
                        imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                            @(state)setBYStixels(obj, state.frame - preF));
                    else
                        imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                            @(state)setRGBStixels(obj, state.frame - preF));
                    end
                else
                    imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                        @(state)setStixels(obj, state.frame - preF));
                end
                p.addController(imgController);

                % Position controller
                if obj.stepsPerStixel > 1
                    xyController = stage.builtin.controllers.PropertyController(checkerboard, 'position',...
                        @(state)setJitter(obj, state.frame - preF));
                    p.addController(xyController);
                end
            else
                spot = stage.builtin.stimuli.Rectangle();
                spot.size = obj.canvasSize;
                spot.position = obj.canvasSize/2;
                spot.orientation = 0;
                spot.color = obj.bkg;
            
                % Add the stimulus to the presentation.
                p.addStimulus(spot);
                
                % Control the spot color.
                colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                    @(state)getSpotAchromatic(obj, state.time - obj.preTime * 1e-3));
                p.addController(colorController);
                
                % Control when the spot is visible.
                spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(spotVisible); 
            end
            
            function s = setStixels(obj, frame)
                persistent M;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        M = (obj.noiseStream.rand(obj.numYStixels,obj.numXStixels)>0.5);
                        M = obj.contrast_seq(frame)*(2*M-1);
                        M = repmat(M,[1,1,3]);
                        for jj = 1 : 3
                            M(:,:,jj) = obj.bg_seq(frame,jj)*M(:,:,jj)+obj.bg_seq(frame,jj);
                        end
                    end
                else
                    M = obj.imageMatrix;
                end
                s = uint8(255*M);
            end
            
            % Blue-Yellow noise
            function s = setBYStixels(obj, frame)
                persistent M;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        M = zeros(obj.numYStixels,obj.numXStixels,3);
                        tmpM = (obj.noiseStream.rand(obj.numYStixels,obj.numXStixels,2)>0.5);
%                         tmpM = tmpM*obj.backgroundIntensity + obj.backgroundIntensity;
                        M(:,:,1:2) = repmat(tmpM(:,:,1),[1,1,2]);
                        M(:,:,3) = tmpM(:,:,2);
                        M = obj.contrast_seq(frame)*(2*M-1);
                        for jj = 1 : 3
                            M(:,:,jj) = obj.bg_seq(frame,jj)*M(:,:,jj)+obj.bg_seq(frame,jj);
                        end
                    end
                else
                    M = obj.imageMatrix;
                end
                s = uint8(255*M);
            end
            
            % RGB noise
            function s = setRGBStixels(obj, frame)
                persistent M;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        M = (obj.noiseStream.rand(obj.numYStixels,obj.numXStixels,3)>0.5);
                        M = obj.contrast_seq(frame)*(2*M-1);
                        for jj = 1 : 3
                            M(:,:,jj) = obj.bg_seq(frame,jj)*M(:,:,jj)+obj.bg_seq(frame,jj);
                        end
                    end
                else
                    M = obj.imageMatrix;
                end
                s = uint8(255*M);
            end
            
            function p = setJitter(obj, frame)
                persistent xy;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        xy = obj.stixelShiftPix*round((obj.stepsPerStixel-1)*(obj.positionStream.rand(1,2))) ...
                            + obj.canvasSize / 2;
                    end
                else
                    xy = obj.canvasSize / 2;
                end
                p = xy;
            end
            
            function c = getSpotAchromatic(obj, time)
                if time > 0 && time <= obj.stimTime*1e-3
                    c = obj.frameSeq(floor(time*obj.frameRate)+1,:);
                else
                    c = obj.bkg;
                end
            end
        end
  
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.frameDwell = obj.frameDwells(mod(obj.numEpochsCompleted, length(obj.frameDwells))+1);
            
            % Deal with the seed.
            if obj.randsPerRep == 0 
                obj.seed = 1;
            elseif obj.randsPerRep < 0
                if obj.numEpochsCompleted == 0
                    obj.seed = RandStream.shuffleSeed;
                else
                    obj.seed = obj.seed + 1;
                end
            elseif obj.randsPerRep > 0 && (mod(obj.numEpochsCompleted+1,obj.randsPerRep+1) == 0)
                obj.seed = 1;
            else
                if obj.numEpochsCompleted == 0
                    obj.seed = RandStream.shuffleSeed;
                else
                    obj.seed = obj.seed + 1;
                end
            end
            
            % Seed the random number generator.
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            % Get the contrast series. [0.05 to 0.35 RMS contrast]
            obj.contrasts = (obj.maxContrast-obj.minContrast)*obj.noiseStream.rand(1, length(obj.durations)) + obj.minContrast;
            
            %obj.backgroundColors = {'sky','trees','grass'}; %{'gray','blue-gray','yellow-gray'};
            num_steps = ceil(obj.stimTime/obj.stepDuration);
            switch obj.backgroundClass
                case 'equal_catch'
                    background_rgb = [0.249,0.249,0.5;0.196,0.196,0.196;0.296,0.296,0.147]; %[0.137*ones(1,3);0.25,0,0.5;0.175,0.175,0];
                case 'equal_luminance'
                    background_rgb = [0.37,0.45,0.5;0.39,0.45,0.48;0.49,0.46,0.38]; %[0.123*ones(1,3);0.25,0,0.5;0.15,0.15,0];
                otherwise
                    background_rgb = [0.37,0.45,0.5;0.4,0.47,0.5;0.5,0.47,0.39]; %[0.5*ones(1,3);0.25,0.25,0.5;0.5,0.5,0.25];
            end
            obj.background_means = background_rgb(2,:);
            
            background_mean_idx = floor(obj.noiseStream.rand(1,num_steps)*(length(obj.backgroundColors)-eps)+1);
            
            % Re-seed the random number generator.
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            % Pre-generate frames for the epoch.
            nframes = obj.stimTime*1e-3*obj.frameRate + ceil(1.5*obj.stimTime*1e-3); 
            eFrames = cumsum(obj.durations*1e-3*obj.frameRate);
            sFrames = [0 eFrames(1:end-1)]+1;
            eFrames(end) = nframes;
            
            if strcmp(obj.stimulusClass, 'spatial')
                obj.bg_seq = zeros(nframes,3);
                obj.contrast_seq = zeros(nframes,1);
                for jj = 1 : length(sFrames)
                    bg = background_rgb(background_mean_idx(jj),:);
                    obj.bg_seq(sFrames(jj):eFrames(jj),:) = ones(length(sFrames(jj):eFrames(jj)),1)*bg;
                    obj.contrast_seq(sFrames(jj):eFrames(jj)) = obj.contrasts(jj);
                end
                
                % Get the current stixel size.
                obj.stixelSize = obj.stixelSizes(mod(obj.numEpochsCompleted, length(obj.stixelSizes))+1);
                obj.stepsPerStixel = max(round(obj.stixelSize / obj.gridSize), 1);

                gridSizePix = obj.rig.getDevice('Stage').um2pix(obj.gridSize);
                obj.stixelSizePix = gridSizePix * obj.stepsPerStixel;
                obj.stixelShiftPix = obj.stixelSizePix / obj.stepsPerStixel;

                % Calculate the number of X/Y checks.
                obj.numXStixels = ceil(obj.canvasSize(1)/obj.stixelSizePix) + 1;
                obj.numYStixels = ceil(obj.canvasSize(2)/obj.stixelSizePix) + 1;
                obj.numXChecks = ceil(obj.canvasSize(1)/gridSizePix);
                obj.numYChecks = ceil(obj.canvasSize(2)/gridSizePix);

                % Seed the generator
                obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
                obj.positionStream = RandStream('mt19937ar', 'Seed', obj.seed);
                epoch.addParameter('numXChecks', obj.numXChecks);
                epoch.addParameter('numYChecks', obj.numYChecks);
                epoch.addParameter('numFrames', obj.numFrames);
                epoch.addParameter('numXStixels', obj.numXStixels);
                epoch.addParameter('numYStixels', obj.numYStixels);
                epoch.addParameter('stixelSize', obj.gridSize*obj.stepsPerStixel);
                epoch.addParameter('stepsPerStixel', obj.stepsPerStixel);
            else
                [fseq, ~,obj.contrasts] = manookinlab.util.getAdaptNoiseStepFrames(...
                    nframes, obj.durations, sFrames, eFrames, obj.seed,...
                    'maxContrast', obj.maxContrast, ...
                    'minContrast', obj.minContrast, ...
                    'noiseClass', obj.noiseClass, ...
                    'stimulusClass',obj.stimulusClass);
                
                obj.frameSeq = zeros(length(fseq),3);
                if ~strcmp(obj.chromaticClass,'achromatic') && isempty(strfind(obj.rig.getDevice('Stage').name, 'LightCrafter'))
                    if strcmp(obj.chromaticClass,'BY')
                        [fseq2, ~,~] = manookinlab.util.getAdaptNoiseStepFrames(...
                            nframes, obj.durations, sFrames, eFrames, obj.seed+1,...
                            'maxContrast', obj.maxContrast, ...
                            'minContrast', obj.minContrast, ...
                            'noiseClass', obj.noiseClass, ...
                            'stimulusClass',obj.stimulusClass);
                        for jj = 1 : length(sFrames)
                            bg = background_rgb(background_mean_idx(jj),:);
                            fvals = fseq(sFrames(jj):eFrames(jj));
                            obj.frameSeq(sFrames(jj):eFrames(jj),1:2) = fvals(:)*bg(1:2) + ones(length(fvals),1)*bg(1:2);
                            fvals2 = fseq2(sFrames(jj):eFrames(jj));
                            obj.frameSeq(sFrames(jj):eFrames(jj),3) = fvals2(:)*bg(3) + ones(length(fvals2),1)*bg(3);
                        end
                    end
                else
                    for jj = 1 : length(sFrames)
                        bg = background_rgb(background_mean_idx(jj),:);
                        fvals = fseq(sFrames(jj):eFrames(jj));
                        obj.frameSeq(sFrames(jj):eFrames(jj),:) = fvals(:)*bg + ones(length(fvals),1)*bg;
                    end
                end
            end
            
            % Save the epoch-specific parameters.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('frameDwell', obj.frameDwell);
            epoch.addParameter('backgroundColors',backgroundColors);
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
