classdef AdaptNoiseLuminanceSteps < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Noise leading duration (ms)
        uniqueTime = 180000             % Duration of unique noise sequence (ms)
        repeatTime = 0                  % Duration of repeating sequence at end of epoch (ms)
        tailTime = 250                  % Noise trailing duration (ms)
        stepDuration = 5000             % Duration series (ms)
        monitorMeans = [0.5,0.02]
        gainMeans = [1,0.025]
        contrasts = [1,1]
        stixelSizes = [150,150]           % Edge length of stixel (microns)
        gridSize = 30                   % Size of underling grid
        randomSeedSequence = 'every 2 epochs' % Determines how many epochs between updates to noise seed.
        frameDwells = uint16([1,1])     % Frame dwell.
        chromaticClass = 'BY'           % Chromatic type
        onlineAnalysis = 'none'
        numberOfAverages = uint16(10)   % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary', 'ternary', 'gaussian'})
        chromaticClassType = symphonyui.core.PropertyType('char','row',{'achromatic','RGB','BY'})
        stixelSizesType = symphonyui.core.PropertyType('denserealdouble','matrix')
        frameDwellsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        monitorMeansType = symphonyui.core.PropertyType('denserealdouble','matrix')
        gainMeansType = symphonyui.core.PropertyType('denserealdouble','matrix')
        randomSeedSequenceType = symphonyui.core.PropertyType('char','row',{'every epoch','every 2 epochs','every 3 epochs','repeat seed'})
        stixelSize
        stepsPerStixel
        numXStixels
        numYStixels
        numXChecks
        numYChecks
        seed
        numFrames
        stixelSizePix
        stixelShiftPix
        imageMatrix
        noiseStream
        positionStream
        noiseStreamRep
        positionStreamRep
        frameDwell
        start_seed
        pre_frames
        step_frames
        unique_frames
        repeat_frames
        step_duration_ms
        time_multiple
        num_steps
        mean_steps
        backgroundIntensity
        projector_gain_device
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end

    methods
        function didSetRig(obj)
            didSetRig@manookinlab.protocols.ManookinLabStageProtocol(obj);

            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            % Get the number of frames.
            obj.numFrames = floor(obj.stimTime * 1e-3 * obj.frameRate)+15;
            obj.pre_frames = round(obj.preTime * 1e-3 * 60.0);
            obj.unique_frames = round(obj.uniqueTime * 1e-3 * 60.0);
            obj.repeat_frames = round(obj.repeatTime * 1e-3 * 60.0);
            obj.step_frames = round(obj.stepDuration * 1e-3 * 60.0);
            obj.step_duration_ms = obj.step_frames * 59.94;
            % Calculate the number of steps.
            obj.num_steps = ceil(obj.stimTime/obj.stepDuration);
            
            % Check for a projector gain device.
            projector_gain = obj.rig.getDevices('Projector Gain');
            if ~isempty(projector_gain)
                obj.projector_gain_device = true;
            else
                obj.projector_gain_device = false;
                obj.gainMeans = ones(size(obj.gainMeans));
            end
        end

        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            obj.imageMatrix = obj.backgroundIntensity * ones(obj.numYStixels,obj.numXStixels);
            checkerboard = stage.builtin.stimuli.Image(uint8(obj.imageMatrix));
            checkerboard.position = obj.canvasSize / 2;
            checkerboard.size = [obj.numXStixels, obj.numYStixels] * obj.stixelSizePix;

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
            
            function s = setStixels(obj, frame)
                persistent M;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        m_idx = min(floor(frame/obj.step_frames) + 1, length(obj.mean_steps));
                        if frame <= obj.unique_frames
                            M = 2* (obj.noiseStream.rand(obj.numYStixels,obj.numXStixels)>0.5)-1;
                        else
                            M = (2*(obj.noiseStream.rand(obj.numYStixels,obj.numXStixels)>0.5)-1);
                        end
                        M = M*obj.mean_steps(m_idx) + obj.mean_steps(m_idx);
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
                        m_idx = min(floor(frame/obj.step_frames) + 1, length(obj.mean_steps));
                        if frame <= obj.unique_frames
                            M = 2*(obj.noiseStream.rand(obj.numYStixels,obj.numXStixels,3)>0.5)-1;
                        else
                            M = (2*(obj.noiseStream.rand(obj.numYStixels,obj.numXStixels,3)>0.5)-1);
                        end
                        M = M*obj.mean_steps(m_idx) + obj.mean_steps(m_idx);
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
                        m_idx = min(floor(frame/obj.step_frames) + 1, length(obj.mean_steps));
                        M = zeros(obj.numYStixels,obj.numXStixels,3);
                        if frame <= obj.unique_frames
                            tmpM = 2*(obj.noiseStream.rand(obj.numYStixels,obj.numXStixels,2)>0.5)-1;
                        else
                            tmpM = (2*(obj.noiseStreamRep.rand(obj.numYStixels,obj.numXStixels,2)>0.5)-1);
                        end
                        tmpM = tmpM*obj.mean_steps(m_idx) + obj.mean_steps(m_idx);
                        M(:,:,1:2) = repmat(tmpM(:,:,1),[1,1,2]);
                        M(:,:,3) = tmpM(:,:,2);
                    end
                else
                    M = obj.imageMatrix;
                end
                s = single(M);
            end
            
            function p = setJitter(obj, frame)
                persistent xy;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        if frame <= obj.unique_frames
                            xy = obj.stixelShiftPix*round((obj.stepsPerStixel-1)*(obj.positionStream.rand(1,2))) ...
                                + obj.canvasSize / 2;
                        else
                            xy = obj.stixelShiftPix*round((obj.stepsPerStixel-1)*(obj.positionStreamRep.rand(1,2))) ...
                                + obj.canvasSize / 2;
                        end
                    end
                else
                    xy = obj.canvasSize / 2;
                end
                p = xy;
            end
        end
        
        function stim = createGainStimulus(obj, gain_values)

            gen = edu.washington.riekelab.stimuli.ProjectorGainGenerator();
            
            gen.preTime = obj.preTime;
            gen.stimTime = obj.stimTime;
            gen.tailTime = obj.tailTime;
            gen.stepDuration = obj.step_duration_ms;
            gen.gain_values = gain_values;
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice( 'Projector Gain' ).background.displayUnits;
            if strcmp(gen.units, symphonyui.core.Measurement.NORMALIZED)
                gen.upperLimit = 1;
                gen.lowerLimit = 0;
            else
                gen.upperLimit = 1.8;
                gen.lowerLimit = -1.8;
            end
            
            stim = gen.generate();
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
            
            % Get the current stixel size.
            obj.stixelSize = obj.stixelSizes(mod(obj.numEpochsCompleted, length(obj.stixelSizes))+1);
            obj.frameDwell = obj.frameDwells(mod(obj.numEpochsCompleted, length(obj.frameDwells))+1);
            
            obj.backgroundIntensity = 0.5;
            
            % Deal with the seed.
            if obj.numEpochsCompleted == 0
                obj.start_seed = RandStream.shuffleSeed;
                obj.seed = obj.start_seed;
            else
                switch obj.randomSeedSequence
                    case 'every epoch'
                        obj.seed = obj.start_seed + 1;
                    case 'every 2 epochs'
                        obj.seed = obj.start_seed + floor(obj.numEpochsCompleted/2);
                    case 'every 3 epochs'
                        obj.seed = obj.start_seed + floor(obj.numEpochsCompleted/3);
                    case 'repeat seed'
                        obj.seed = 1;
                end
            end

            obj.stepsPerStixel = max(round(obj.stixelSize / obj.gridSize), 1);
            
            gridSizePix = obj.rig.getDevice('Stage').um2pix(obj.gridSize);
            %obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
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
            obj.noiseStreamRep = RandStream('mt19937ar', 'Seed', 1);
            obj.positionStreamRep = RandStream('mt19937ar', 'Seed', 1);
            
            stepStream = RandStream('mt19937ar', 'Seed', obj.seed);
            mean_idx = floor(stepStream.rand(1, obj.num_steps) * length(obj.monitorMeans)) + 1;
            obj.mean_steps = obj.monitorMeans( mean_idx );
            % Create the gain stimulus.
            if obj.projector_gain_device
                epoch.addStimulus( obj.rig.getDevice( 'Projector Gain' ), obj.createGainStimulus( obj.gainMeans( mean_idx ) ) );
            end
            
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('repeating_seed',1);
            epoch.addParameter('numXChecks', obj.numXChecks);
            epoch.addParameter('numYChecks', obj.numYChecks);
            epoch.addParameter('numFrames', obj.numFrames);
            epoch.addParameter('numXStixels', obj.numXStixels);
            epoch.addParameter('numYStixels', obj.numYStixels);
            epoch.addParameter('stixelSize', obj.gridSize*obj.stepsPerStixel);
            epoch.addParameter('stepsPerStixel', obj.stepsPerStixel);
            epoch.addParameter('frameDwell', obj.frameDwell);
            epoch.addParameter('num_steps', obj.num_steps);
            epoch.addParameter('pre_frames', obj.pre_frames);
            epoch.addParameter('unique_frames', obj.unique_frames);
            epoch.addParameter('repeat_frames', obj.repeat_frames);
            epoch.addParameter('step_frames', obj.step_frames);
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
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.uniqueTime + obj.repeatTime;
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
        function completeRun(obj)
            completeRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
        end
    end
end
