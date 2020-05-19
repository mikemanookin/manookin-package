classdef Glider2Contrasts < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 12000                % Stimulus duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        waitTime = 0                    % Stimulus wait duration (ms)
        stixelSize = 50                 % Stixel edge size (microns)
        contrasts = [0.25, 0.5, 1]      % Contrast (0 - 1)
        contrastDistribution = 'binary' % Contrast distribution ('gaussian','binary','uniform')
        orientation = 0                 % Texture orientation (degrees)
        dimensionality = '1-d'          % Stixel dimensionality
        stimulusClass = 'on'
        innerRadius = 0                 % Inner mask radius in microns.
        outerRadius = 1000              % Outer mask radius in microns.
        randsPerRep = 20                 % Number of random seeds per repeat
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Online analysis type.
        numberOfAverages = uint16(210)  % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        dimensionalityType = symphonyui.core.PropertyType('char', 'row', {'1-d', '2-d'});
        contrastDistributionType = symphonyui.core.PropertyType('char','row', {'gaussian','binary','uniform'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'on', 'off', 'all', '2+3', '3-point', '3-point positive', '3-point negative', '2+3 positive', '2+3 negative', 'diverging positive', 'diverging negative', 'uncorrelated'});
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
        innerRadiusPix
        outerRadiusPix
        contrast
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            obj.innerRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.innerRadius);
            obj.outerRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.outerRadius);

            switch obj.stimulusClass
                case 'all'
                    obj.stimulusNames = {'uncorrelated', '2-point positive', '2-point negative', '3-point diverging positive', '3-point converging positive', '3-point diverging negative', '3-point converging negative'};
                case '2+3'
                    obj.stimulusNames = {'uncorrelated', '2-point positive', '3-point diverging positive', '3-point converging positive', '3-point diverging negative', '3-point converging negative'};
                case '3-point'
                    obj.stimulusNames = {'uncorrelated', '3-point diverging positive', '3-point converging positive', '3-point diverging negative', '3-point converging negative'};
                case '3-point positive'
                    obj.stimulusNames = {'uncorrelated', '3-point diverging positive', '3-point converging positive'};
                case '3-point negative'
                    obj.stimulusNames = {'uncorrelated', '3-point diverging negative', '3-point converging negative'};
                case '2+3 positive'
                    obj.stimulusNames = {'uncorrelated', '2-point positive', '3-point diverging positive', '3-point converging positive'};
                case '2+3 negative'
                    obj.stimulusNames = {'uncorrelated', '2-point positive', '3-point diverging negative', '3-point converging negative'};
                case 'diverging positive'
                    obj.stimulusNames = {'uncorrelated', '3-point diverging positive'};
                case 'diverging negative'
                    obj.stimulusNames = {'uncorrelated', '3-point diverging negative'};
                case 'on'
                    obj.stimulusNames = {'uncorrelated', '2-point positive', '3-point diverging positive'};
                case 'off'
                    obj.stimulusNames = {'uncorrelated', '2-point positive', '3-point diverging negative'};
                otherwise
                    obj.stimulusNames = {'uncorrelated'};
            end
            
            if length(obj.stimulusNames) > 1
                colors = pmkmp(length(obj.stimulusNames),'CubicYF');
            else
                colors = [0 0 0];
            end
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',colors,...
                    'groupBy',{'stimulusType'});

                obj.showFigure('manookinlab.figures.ShiftedInformationFigure', ...
                    obj.rig.getDevice(obj.amp), 'recordingType',obj.onlineAnalysis,...
                    'preTime', obj.preTime, ...
                    'stimTime', obj.stimTime, ...
                    'frameRate', obj.frameRate, ...
                    'groupBy', 'stimulusType',...
                    'groupByValues', obj.stimulusNames);
            end
            
            % Calculate the number of frames.
            obj.numStimFrames = ceil(obj.stimTime/1000*obj.frameRate) + 10;
            
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
            
            % Get the correlation sequence.
            obj.sequence = ones(length(obj.contrasts),1) * (1 : length(obj.stimulusNames));
            obj.sequence = obj.sequence(:) * ones(1, ceil(obj.numberOfAverages/length(obj.stimulusNames)));
            obj.sequence = obj.sequence(:)';
            % Just take the ones you need.
            obj.sequence = obj.sequence( 1 : obj.numberOfAverages );
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
            elseif obj.randsPerRep > 0 && (mod(floor(obj.numEpochsCompleted/length(obj.stimulusNames)),obj.randsPerRep+1) == 0)
                obj.seed = 1;
            else
                obj.seed = RandStream.shuffleSeed;
            end
            
            % Seed the random number generator.
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            % Get the stimulus type and parity.
            tmp = obj.stimulusNames{obj.sequence( obj.numEpochsCompleted+1 )};
            
            % Get the current contrast.
            obj.contrast = obj.contrasts(mod(obj.numEpochsCompleted, length(obj.contrasts))+1);
            
            
            if ~contains(tmp,'uncorrelated')
                % Check parity.
                if contains(tmp,'negative')
                    obj.parity = 'negative';
                    obj.stimulusType = strrep(tmp,' negative','');
                else
                    obj.parity = 'positive';
                    obj.stimulusType = strrep(tmp,' positive','');
                end
            else
                obj.stimulusType = tmp;
            end
            
            % Generate the frame sequence
            if strcmp(obj.stimulusType, 'uncorrelated')
                obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
                obj.frameSequence = (obj.noiseStream.rand(obj.numYChecks, obj.numXChecks, ...
                    obj.numStimFrames) > 0.5);
            else
                % Get the glider matrix.
                switch obj.stimulusType
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
            
                obj.frameSequence = makeGlider(obj.numYChecks, obj.numXChecks, ...
                    obj.numStimFrames, glider, par, obj.seed);
            end
            % Set the contrast.
            obj.frameSequence = (2 * obj.frameSequence - 1);
            
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
            
            % Calculate the 3-pt correlations
%             c = obj.getThreePtCorr(tmp);
%             c = squeeze(sum(sum(c,1),2));
            c = manookinlab.util.getTemporalCorrelations(obj.frameSequence, tmp);
            c = c(:)';
            
            % Convert to contrast.
            obj.frameSequence = obj.frameSequence*obj.backgroundIntensity + obj.backgroundIntensity;
%             obj.frameSequence(obj.frameSequence <= 0) = obj.frameSequence(obj.frameSequence <= 0)*obj.backgroundIntensity + obj.backgroundIntensity;
            % Convert to 8-bit integer.
            obj.frameSequence = uint8(obj.frameSequence * 255);
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('numXChecks', obj.numXChecks);
            epoch.addParameter('numYChecks', obj.numYChecks);
            epoch.addParameter('stimulusType', tmp);
            epoch.addParameter('correlationSequence',c);
            epoch.addParameter('contrast',obj.contrast);
        end
        
        % Calculate the 3-pt correlations
        function c = getThreePtCorr(obj, stimulusType)
            S = obj.frameSequence;
            c = zeros(size(S));

            % Diverging correlations
            if contains(stimulusType,'diverging')
                if ismatrix(c)
                    for k = 2 : size(S,1)
                        c(k,2:end) = S(k,1:end-1) .* ((S(k,2:end) + S(k-1,2:end))/2);
                    end
                else
                    for k = 2 : size(S,1)
                        for m = 1 : size(S,2)
                            c(k,m,2:end) = S(k,m,1:end-1) .* ((S(k,m,2:end) + S(k-1,m,2:end))/2);
                        end
                    end
                end
            else
                if ismatrix(c)
                    for k = 2 : size(S,1)
                        c(k,2:end) = S(k,2:end) .* ((S(k,1:end-1) + S(k-1,1:end-1))/2);
                    end
                else
                    for k = 2 : size(S,1)
                        for m = 1 : size(S,2)
                            c(k,m,2:end) = S(k,m,2:end) .* ((S(k,m,1:end-1) + S(k-1,m,1:end-1))/2);
                        end
                    end
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