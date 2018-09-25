classdef SequentialVsRandomBars < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 1000                 % Stimulus duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        waitTime = 750                  % Stimulus wait time (ms)
        frameDwell = 1                  % Frame dwell
        barSize = [150 1200]              % Bar size (pixels)
        numberOfBars = 8                % Number of bars
        contrast = 0.5                  % Bar contrast (-1 : 1)
        orientation = 0                 % Bar orientation (degrees)
        gratingContrast = 0.0           % Grating contrast (0-1)
        gratingBarWidth = 50            % Grating bar width (pix)
        gratingApertureRadius = 250     % Grating aperture radius (pix)
        gratingTemporalFrequency = 4.0  % Grating temporal frequency (Hz)
        gratingTemporalClass = 'reversing' % Grating temporal type.
        gratingSpatialClass = 'squarewave' % Grating spatial type
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Online analysis type.
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        numberOfAverages = uint16(50)  % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        gratingTemporalClassType = symphonyui.core.PropertyType('char', 'row', {'reversing', 'drifting'})
        gratingSpatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        sequenceNames = {'sequential', 'random'}
        sequenceName
        sequence
        seed
        frameSequence
        latticeSize
        actualStimFrames
        phaseShift
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if length(obj.sequenceNames) > 1
                colors = pmkmp(length(obj.sequenceNames),'CubicYF');
            else
                colors = [0 0 0];
            end
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'sequenceName'});
            
            % Get the correlation sequence.
            numReps = ceil(double(obj.numberOfAverages)/length(obj.sequenceNames));
            obj.sequence = (1 : length(obj.sequenceNames))' * ones(1, numReps);
            obj.sequence = obj.sequence(:)';
            % Just take the ones you need.
            obj.sequence = obj.sequence( 1 : obj.numberOfAverages );
            
            % Get the number of actual stimulus frames.
            obj.actualStimFrames = obj.frameDwell * obj.numberOfBars;
        end
        
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create the surround grating.
            if obj.gratingContrast > 0                
                switch obj.gratingSpatialClass
                    case 'sinewave'
                        grate = stage.builtin.stimuli.Grating('sine');
                    otherwise % Square-wave grating
                        grate = stage.builtin.stimuli.Grating('square'); 
                end
                grate.orientation = 0;
                grate.size = obj.canvasSize;
                grate.position = obj.canvasSize/2 + obj.centerOffset;
                grate.spatialFreq = 1/(2*obj.gratingBarWidth); %convert from bar width to spatial freq
                grate.contrast = obj.gratingContrast;
                grate.color = 2*obj.backgroundIntensity;
                %calc to apply phase shift s.t. a contrast-reversing boundary
                %is in the center regardless of spatial frequency. Arbitrarily
                %say boundary should be positve to right and negative to left
                %crosses x axis from neg to pos every period from 0
                zeroCrossings = 0:(grate.spatialFreq^-1):grate.size(1); 
                offsets = zeroCrossings-grate.size(1)/2; %difference between each zero crossing and center of texture, pixels
                [shiftPix, ~] = min(offsets); % min(offsets(offsets>0)); %positive shift in pixels
                phaseShift_rad = (shiftPix/(grate.spatialFreq^-1))*(2*pi); %phaseshift in radians
                obj.phaseShift = 360*(phaseShift_rad)/(2*pi); %phaseshift in degrees
                grate.phase = obj.phaseShift; %keep contrast reversing boundary in center

                % Add the grating.
                p.addStimulus(grate);

                % Make the grating visible only during the stimulus time.
                grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(grateVisible);

                %--------------------------------------------------------------
                % Control the grating phase.
                if strcmp(obj.gratingTemporalClass, 'drifting')
                    grateController = stage.builtin.controllers.PropertyController(grate, 'phase',...
                        @(state)setDriftingGrating(obj, state.time - obj.preTime * 1e-3));
                else
                    grateController = stage.builtin.controllers.PropertyController(grate, 'phase',...
                        @(state)setReversingGrating(obj, state.time - obj.preTime * 1e-3));
                end
                p.addController(grateController);
                
                % Create the aperture.
                if obj.gratingApertureRadius > 0 && obj.gratingApertureRadius < min(obj.canvasSize/2)
                    bg = stage.builtin.stimuli.Ellipse();
                    bg.color = obj.backgroundIntensity;
                    bg.radiusX = obj.gratingApertureRadius;
                    bg.radiusY = obj.gratingApertureRadius;
                    bg.position = obj.canvasSize/2 + obj.centerOffset;
                    p.addStimulus(bg);
                end
            end
            
            % Create the stimulus.
            bars = stage.builtin.stimuli.Image(squeeze(obj.frameSequence(:,:,1)));
            bars.position = obj.canvasSize/2 + obj.centerOffset;
            bars.size = obj.latticeSize;
            bars.orientation = obj.orientation;

            % Set the minifying and magnifying functions to form discrete
            % stixels.
            bars.setMinFunction(GL.NEAREST);
            bars.setMagFunction(GL.NEAREST);

            % Add the stimulus to the presentation.
            p.addStimulus(bars);

            gridVisible = stage.builtin.controllers.PropertyController(bars, 'visible', ...
                @(state)state.time >= (obj.preTime+obj.waitTime) * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(gridVisible);
            
            imgController = stage.builtin.controllers.PropertyController(bars, 'imageMatrix',...
                @(state)frameSeq(obj, state.time - (obj.preTime+obj.waitTime)*1e-3));
%             imgController = stage.builtin.controllers.PropertyController(bars, 'imageMatrix',...
%                 @(state)getBarFrame(obj, state.frame - floor((obj.preTime+obj.waitTime)*1e-3)*obj.frameRate, size(obj.frameSequence,3)));
            p.addController(imgController);
            
            function s = frameSeq(obj, time)
                if time >= 0 && time <= (obj.stimTime+obj.waitTime)*1e-3;
                    frame = floor(obj.frameRate * time) + 1;
                    s = squeeze(obj.frameSequence(:, :, frame));
                else
                    s = squeeze(obj.frameSequence(:, :, 1));
                end
            end
            
%             function s = getBarFrame(obj, frame, stimFrames)
%                 if frame > 0 && frame <= stimFrames
%                     s = squeeze(obj.frameSequence(:, :, frame));
%                 else
%                     s = squeeze(obj.frameSequence(:, :, 1));
%                 end
%             end
            
            % Set the drifting grating.
            function phase = setDriftingGrating(obj, time)
                if time >= 0
                    phase = obj.gratingTemporalFrequency * time * 2 * pi;
                else
                    phase = 0;
                end

                phase = phase*180/pi + obj.phaseShift;
            end

            % Set the reversing grating
            function phase = setReversingGrating(obj, time)
                if time >= 0
                    phase = round(0.5 * sin(time * 2 * pi * obj.gratingTemporalFrequency) + 0.5) * pi;
                else
                    phase = 0;
                end

                phase = phase*180/pi + obj.phaseShift;
            end
        end
        
        function barSeq = generateFrameSequence(obj)
            % Get the lattice size.
            obj.latticeSize = [obj.numberOfBars*obj.barSize(1) obj.barSize(2)];
            
            % Calculate the total number of frames.
            numFrames = ceil(obj.stimTime*1e-3*obj.frameRate) + 10;
            numFrames = max(numFrames, obj.actualStimFrames);
            obj.frameSequence = zeros(obj.numberOfBars, numFrames);
            
            % Generate the frame sequence based on the sequence name.
            if strcmp(obj.sequenceName, 'sequential')
                barSeq = 1 : obj.numberOfBars;
            else
                noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
                % Make sure you have a minimally-tilted sequence.
                % Generating untilted stimuli with 4 bars is really tricky.
                if obj.numberOfBars == 4
                    u = [
                        1 3 4 2;
                        1 4 2 3;
                        2 3 1 4;
                        2 4 1 3;
                        3 2 4 1;
                        4 1 3 2;
                        2 4 1 3;
                        3 1 4 2;
                        4 2 1 3;
                        ];
                    barSeq = u(ceil(noiseStream.rand*size(u,1)),:);
                else
                    barSeq = noiseStream.randperm(obj.numberOfBars);
                end
            end
%             switch obj.sequenceName
%                 case 'sequential'
%                     barSeq = 1 : obj.numberOfBars;
%                 otherwise
%                     noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
%                     barSeq = noiseStream.randperm(obj.numberOfBars);
%             end
            
            if obj.frameDwell > 1
                barSeq = ones(obj.frameDwell,1)*barSeq;
                barSeq = barSeq(:)';
            end
            
            for k = 1 : length(barSeq)
                obj.frameSequence(barSeq(k), k) = obj.contrast;
            end
            
            % Convert from contrast to intensity.
            if obj.backgroundIntensity >= 0.25
                obj.frameSequence = obj.backgroundIntensity*obj.frameSequence+obj.backgroundIntensity;
            else
                obj.frameSequence(obj.frameSequence==0) = obj.backgroundIntensity;
            end
            
            % Make it 3-D.
            tmp(1,:,:) = obj.frameSequence;
            obj.frameSequence = tmp;
            clear tmp;
            
            % Convert to 8-bit.
            obj.frameSequence = uint8(obj.frameSequence*255);
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current sequence name.
            obj.sequenceName = obj.sequenceNames{obj.sequence( obj.numEpochsCompleted+1 )};
            
            % Get the seed if it's a random sequence.
            if strcmp(obj.sequenceName, 'random')
                obj.seed = RandStream.shuffleSeed;
                epoch.addParameter('seed', obj.seed);
            end

            % Save the sequence name
            epoch.addParameter('sequenceName', obj.sequenceName);
            epoch.addParameter('actualStimFrames', obj.actualStimFrames);
            
            % Generate the frame sequence.
            barSeq = obj.generateFrameSequence();
            epoch.addParameter('barSequence', barSeq);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end