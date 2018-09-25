classdef GliderRings < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 6000                 % Stimulus duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        waitTime = 1000                 % Stimulus wait duration (ms)
        contrast = 1.0                  % Stimulus contrast (0-1)
        tiltDirection = 'outward'       % Inward or outward tilt?
        innerRadius = 50                % Inner mask radius in pixels.
        outerRadius = 200               % Outer mask radius in pixels.
        ringWidth = 15                  % Ring width (pix)
        randomSeed = false              % Random or repeating seed
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        onlineAnalysis = 'analog'       % Online analysis type.
        numberOfAverages = uint16(35)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        tiltDirectionType = symphonyui.core.PropertyType('char', 'row', {'outward', 'inward'})
        stimulusNames = {'uncorrelated', '2-point positive', '2-point negative', '3-point diverging positive', '3-point converging positive', '3-point diverging negative', '3-point converging negative'}
        noiseStream
        seed
        numRings
        numStimFrames
        frameSequence
        sequence
        stimulusType
        parity
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if length(obj.stimulusNames) > 1
                colors = pmkmp(length(obj.stimulusNames),'CubicYF');
            else
                colors = [0 0 0];
            end
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'stimulusType'});
            
            % Calculate the number of rings.
            obj.numRings = ceil((obj.outerRadius - obj.innerRadius) / obj.ringWidth);
            
            % Make sure the contrast scales from 0-1.
            obj.contrast = abs(obj.contrast);
            if obj.contrast > 1
                obj.contrast = 1.0;
            end
            
            % Calculate the number of frames.
            obj.numStimFrames = ceil(obj.stimTime/1000*obj.frameRate) + 10;
            
            % Get the correlation sequence.
            obj.sequence = (1 : length(obj.stimulusNames))' * ones(1, obj.numberOfAverages);
            obj.sequence = obj.sequence(:)';
            % Just take the ones you need.
            obj.sequence = obj.sequence( 1 : obj.numberOfAverages );
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            if strcmp(obj.stimulusType, 'uncorrelated')
                obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
                obj.frameSequence = (obj.noiseStream.rand(obj.numRings, 1, ...
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
            
                obj.frameSequence = makeGlider(obj.numRings, 1, ...
                    obj.numStimFrames, glider, par, obj.seed);
            end
            % Squeeze to two dimensions.
            obj.frameSequence = squeeze(obj.frameSequence);
            
            % Set the contrast.
            obj.frameSequence = obj.contrast * (2 * obj.frameSequence - 1);
            % Convert to contrast.
            obj.frameSequence(obj.frameSequence <= 0) = obj.frameSequence(obj.frameSequence <= 0)*obj.backgroundIntensity + obj.backgroundIntensity;

            % Need to transpose at this point so that frames are rows.
            obj.frameSequence = obj.frameSequence';
            
            % Flip the frame sequence for outward tilt.
            if strcmp(obj.tiltDirection, 'inward')
                obj.frameSequence = fliplr(obj.frameSequence);
            end
            
            % Calculate the outer radii.
            radii = obj.outerRadius - obj.ringWidth*(0:obj.numRings-1);

            % Create the rings.
            for k = 1 : obj.numRings
                spot = stage.builtin.stimuli.Ellipse();
                spot.color = obj.backgroundIntensity;
                spot.radiusX = radii(k);
                spot.radiusY = radii(k);
                spot.position = obj.canvasSize/2 + obj.centerOffset;
                p.addStimulus(spot);

                spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(spotVisible);

                % Bar position controller
                spotColor = stage.builtin.controllers.PropertyController(spot, 'color', ...
                    @(state)frameSeq(obj, state.time - (obj.preTime+obj.waitTime)*1e-3, k));
                p.addController(spotColor);
            end
            
            % Great the background inner ring.
            if obj.innerRadius > 0
                bg = stage.builtin.stimuli.Ellipse();
                bg.color = obj.backgroundIntensity;
                bg.radiusX = obj.innerRadius;
                bg.radiusY = obj.innerRadius;
                bg.position = obj.canvasSize/2 + obj.centerOffset;
                p.addStimulus(bg);
            end
            
            function c = frameSeq(obj, time, whichSpot)
                if time >= 0 && time <= obj.stimTime*1e-3;
                    frame = floor(obj.frameRate * time) + 1;
                    c = obj.frameSequence(frame, whichSpot);
                else
                    c = obj.frameSequence(1, whichSpot);
                end
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Deal with the seed.
            if obj.randomSeed
                obj.seed = RandStream.shuffleSeed;
            else
                obj.seed = 1;
            end
            
            % Seed the random number generator.
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            % Get the stimulus type and parity.
            tmp = obj.stimulusNames{obj.sequence( obj.numEpochsCompleted+1 )};
            
            if isempty(strfind(tmp,'uncorrelated'))
                % Check parity.
                if isempty(strfind(tmp,'positive'))
                    obj.parity = 'negative';
                    obj.stimulusType = strrep(tmp,' negative','');
                else
                    obj.parity = 'positive';
                    obj.stimulusType = strrep(tmp,' positive','');
                end
            else
                obj.stimulusType = tmp;
            end
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('numRings', obj.numRings);
            epoch.addParameter('stimulusType', tmp);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end