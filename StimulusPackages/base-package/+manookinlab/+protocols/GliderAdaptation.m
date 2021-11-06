classdef GliderAdaptation < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 8000                 % Stimulus duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        waitTime = 0                    % Stimulus wait duration (ms)
        stixelSize = 50                 % Stixel edge size (microns)
        contrast = 0.1                  % Contrast (0 - 1)
        contrastDistribution = 'binary' % Contrast distribution ('gaussian','binary','uniform')
        orientation = 0                 % Texture orientation (degrees)
        dimensionality = '1-d'          % Stixel dimensionality
        stimulusClass = 'uncorrelated 3-point'
        innerRadius = 0                 % Inner mask radius in microns.
        outerRadius = 1000              % Outer mask radius in microns.
        randsPerRep = 10                % Number of random seeds per repeat (negative value is all random)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Online analysis type.
        numberOfAverages = uint16(120)  % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        dimensionalityType = symphonyui.core.PropertyType('char', 'row', {'1-d', '2-d'});
        contrastDistributionType = symphonyui.core.PropertyType('char','row', {'gaussian','binary','uniform'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'all', '3-point', '3-point positive', '3-point negative','uncorrelated 3-point','3-point diverging positive','3-point converging positive','3-point diverging negative','3-point converging negative'});
        stimulusNames
        noiseStream
        seed
        frameSequence
        numXChecks
        numYChecks
        stixelDims
        numStimFrames
        sequence
        stimulusType
        parity
        stixelSizePix
        stimulusCombinations
        stimulus1
        stimulus2
        innerRadiusPix
        outerRadiusPix
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            obj.outerRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.outerRadius);
            obj.innerRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.innerRadius);

            switch obj.stimulusClass
                case 'all'
                    obj.stimulusNames = {'uncorrelated', '2-point positive', '2-point negative', '3-point diverging positive', '3-point converging positive', '3-point diverging negative', '3-point converging negative'};
                case '3-point'
                    obj.stimulusNames = {'uncorrelated', '3-point diverging positive', '3-point converging positive', '3-point diverging negative', '3-point converging negative'};
                case '3-point positive'
                    obj.stimulusNames = {'uncorrelated', '3-point diverging positive', '3-point converging positive'};
                case '3-point negative'
                    obj.stimulusNames = {'uncorrelated', '3-point diverging negative', '3-point converging negative'};
                case '3-point diverging positive'
                    obj.stimulusNames = {'uncorrelated', '3-point diverging positive'};
                case '3-point converging positive'
                    obj.stimulusNames = {'uncorrelated', '3-point converging positive'};
                case '3-point diverging negative'
                    obj.stimulusNames = {'uncorrelated', '3-point diverging negative'};
                case '3-point converging negative'
                    obj.stimulusNames = {'uncorrelated', '3-point converging negative'};
                case 'uncorrelated 3-point'
                    obj.stimulusNames = {'uncorrelated', '3-point diverging positive', '3-point converging positive', '3-point diverging negative', '3-point converging negative'};
            end
            
            % Calculate the number of frames.
            obj.numStimFrames = ceil(obj.stimTime*1e-3*obj.frameRate) + 10;
            
            % Calculate the size of the stimulus.
            sz = [min(obj.canvasSize(1), obj.outerRadiusPix*2) min(obj.canvasSize(2), obj.outerRadiusPix*2)];
            
            % Calculate the X/Y stixels.
            obj.numYChecks = ceil(sz(2)/obj.stixelSizePix);
            if strcmpi(obj.dimensionality, '1-d')
                obj.numXChecks = 1;
                obj.stixelDims = [sz(1) obj.stixelSizePix];
            else
                obj.numXChecks = ceil(sz(1)/obj.stixelSizePix);
                obj.stixelDims = obj.stixelSizePix*ones(1,2);
            end
            
            % Get all of the possible combinations.
            if strcmpi(obj.stimulusClass, 'uncorrelated 3-point')
                obj.stimulusCombinations = [ones(length(obj.stimulusNames)-1,1) (2:length(obj.stimulusNames))'; (2:length(obj.stimulusNames))' ones(length(obj.stimulusNames)-1,1)];
            else
                tmp = combnk(1 : length(obj.stimulusNames), 2);
            
                % Get all of the possible combinations.
                obj.stimulusCombinations = [tmp; tmp(:,[2 1])];
            end
            
            % Get the correlation sequence.
            obj.sequence = (1 : size(obj.stimulusCombinations,1))' * ones(1, obj.numberOfAverages);
            obj.sequence = obj.sequence(:)';
            % Just take the ones you need.
            obj.sequence = obj.sequence( 1 : obj.numberOfAverages );
            
            if length(obj.stimulusNames) > 1
                colors = pmkmp(size(obj.stimulusCombinations,1),'CubicYF');
            else
                colors = [0 0 0];
            end
            
            % Figures
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'stimulusType'});
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create your noise image.
            imageMatrix = uint8((zeros(obj.numYChecks, obj.numXChecks)) * 255);
            checkerboard = stage.builtin.stimuli.Image(imageMatrix);
            checkerboard.position = obj.canvasSize / 2;
            checkerboard.size = [obj.numXChecks obj.numYChecks] .* obj.stixelDims;
            checkerboard.orientation = obj.orientation;
            
            % Set the minifying and magnifying functions to form discrete
            % stixels.
            checkerboard.setMinFunction(GL.NEAREST);
            checkerboard.setMagFunction(GL.NEAREST);
            
            % Add the stimulus to the presentation.
            p.addStimulus(checkerboard);
            
            %--------------------------------------------------------------
            % Size is 0 to 1
            sz = (obj.outerRadiusPix*2)/min(obj.canvasSize);
            % Create the outer mask.
            if sz < 1
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = obj.canvasSize/2;
                aperture.color = obj.backgroundIntensity;
                aperture.size = obj.canvasSize;
                [x,y] = meshgrid(linspace(-obj.canvasSize(1)/2,obj.canvasSize(1)/2,obj.canvasSize(1)), ...
                    linspace(-obj.canvasSize(2)/2,obj.canvasSize(2)/2,obj.canvasSize(2)));
                distanceMatrix = sqrt(x.^2 + y.^2);
                circle = uint8((distanceMatrix >= obj.outerRadiusPix) * 255);
                mask = stage.core.Mask(circle);
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
            %--------------------------------------------------------------

            gridVisible = stage.builtin.controllers.PropertyController(checkerboard, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(gridVisible);
            
            imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                @(state)frameSeq(obj, state.time - (obj.preTime+obj.waitTime)*1e-3));
            p.addController(imgController);
            
            function s = frameSeq(obj, time)
                if time >= 0 && time <= obj.stimTime*1e-3
                    frame = floor(obj.frameRate * time) + 1;
                    s = squeeze(obj.frameSequence(:, :, frame));
                else
                    s = squeeze(obj.frameSequence(:, :, 1));
                end
            end
            
            % Create the background inner ring.
            if obj.innerRadiusPix > 0
                bg = stage.builtin.stimuli.Ellipse();
                bg.color = obj.backgroundIntensity;
                bg.radiusX = obj.innerRadiusPix;
                bg.radiusY = obj.innerRadiusPix;
                bg.position = obj.canvasSize/2;
                p.addStimulus(bg);
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Deal with the seed.
            if obj.randsPerRep <= 0
                obj.seed = 1;
            elseif obj.randsPerRep > 0 && (mod(floor(obj.numEpochsCompleted/length(obj.stimulusNames))+1,obj.randsPerRep+1) == 0)
                obj.seed = 1;
            else
                obj.seed = RandStream.shuffleSeed;
            end
            
            % Seed the random number generator.
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            % Get the stimulus type and parity.
            tmp = obj.stimulusCombinations(obj.sequence( obj.numEpochsCompleted+1 ),:);
            obj.stimulus1 = obj.stimulusNames{tmp(1)};
            obj.stimulus2 = obj.stimulusNames{tmp(2)};
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('numXChecks', obj.numXChecks);
            epoch.addParameter('numYChecks', obj.numYChecks);
            epoch.addParameter('stimulusType', [obj.stimulus1,' ',obj.stimulus2]);
            epoch.addParameter('halfFrames',ceil(obj.stimTime/1000*obj.frameRate/2));
            
            % Get the frame sequence.
            obj.getFrameSequence();
        end
        
        function getFrameSequence(obj)
            
            % Calculate the half-frames.
            halfFrames = ceil(obj.stimTime/1000*obj.frameRate/2);
            % Get the first half.
            seq = obj.getSequenceFromType(obj.stimulus1);
            % Get the second half
            obj.frameSequence = obj.getSequenceFromType(obj.stimulus2);
            obj.frameSequence(:,:,1:halfFrames) = seq(:,:,1:halfFrames);
            
            switch obj.contrastDistribution
                case 'binary'
                    obj.frameSequence = obj.contrast * obj.frameSequence;
                case 'gaussian'
                    noiseStream2 = RandStream('mt19937ar', 'Seed', obj.seed);
                    obj.frameSequence = obj.contrast * obj.frameSequence .* abs(0.3*noiseStream2.randn(size(obj.frameSequence)));
                case 'uniform'
                    noiseStream2 = RandStream('mt19937ar', 'Seed', obj.seed);
                    obj.frameSequence = obj.contrast * obj.frameSequence .* abs(noiseStream2.rand(size(obj.frameSequence)));
            end
            % Convert to contrast.
            obj.frameSequence = obj.frameSequence*obj.backgroundIntensity + obj.backgroundIntensity;

            % Convert to 8-bit integer.
            obj.frameSequence = uint8(obj.frameSequence * 255);
        end
        
        function seq = getSequenceFromType(obj, seqType)
            
            if ~contains(seqType,'uncorrelated')
                % Check parity.
                if contains(seqType,'positive')
                    obj.parity = 'positive';
                    seqType = strrep(seqType,' positive','');
                else
                    obj.parity = 'negative';
                    seqType = strrep(seqType,' negative','');
                end
            end
            
            if strcmp(seqType, 'uncorrelated')
                obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
                seq = (obj.noiseStream.rand(obj.numYChecks, obj.numXChecks, ...
                    obj.numStimFrames) > 0.5);
            else
                % Get the glider matrix.
                switch seqType
                    case '2-point'
                        glider = [0 1 1; 1 1 0];
                    case '3-point diverging'
                        glider = [0 1 1; 1 1 1; 1 1 0];
                    case '3-point converging'
                        glider = [0 0 0; 1 0 0; 1 0 1];
                end

                % Get the parity.
                switch obj.parity
                    case 'positive'
                        par = 0;
                    otherwise
                        par = 1;
                end
            
                seq = makeGlider(obj.numYChecks, obj.numXChecks, ...
                    obj.numStimFrames, glider, par, obj.seed);
            end
            % Set the contrast.
            seq = (2 * seq - 1);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end