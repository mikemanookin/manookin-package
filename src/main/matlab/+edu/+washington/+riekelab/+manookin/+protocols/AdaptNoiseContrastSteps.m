classdef AdaptNoiseContrastSteps < edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stim leading duration (ms)
        stimTime = 25000                % Stim duration (ms)
        tailTime = 250                  % Stim trailing duration (ms)
        stepDuration = 500              % Duration series (ms)
        radius = 100                    % Inner radius in pixels.
        apertureRadius = 100            % Aperture/blank radius in pixels.
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        noiseClass = 'gaussian'         % Noise type (binary or Gaussian)
        stimulusClass = 'spot'          % Stimulus class
        chromaticClass = 'achromatic'   % Chromatic class
        onlineAnalysis = 'extracellular'% Online analysis type.
        randomSeed = true               % Use random noise seed?
        numberOfAverages = uint16(8)    % Number of epochs
    end
    
    properties (Hidden)
        ampType
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary','gaussian','binary-gaussian'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'spot','center-const-surround','center-full', 'annulus', 'full-field','center-surround'})
        seed
        bkg
        noiseStream
        frameSeq
        frameSeqSurround
        contrasts
        durations
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.manookin.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',[30 144 255]/255,...
                'groupBy',{'frameRate'});
            
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
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            if strcmp(obj.stimulusClass, 'center-full') || strcmp(obj.stimulusClass, 'center-surround') || strcmp(obj.stimulusClass,'center-const-surround')
                surround = stage.builtin.stimuli.Rectangle();
                surround.color = obj.backgroundIntensity;
                surround.orientation = 0;
                if strcmp(obj.stimulusClass, 'center-surround') || strcmp(obj.stimulusClass,'center-const-surround')
                    surround.size = max(obj.canvasSize) * ones(1,2) + 2*max(abs(obj.centerOffset));
                    surround.position = obj.canvasSize/2 + obj.centerOffset;
                    sc = (obj.apertureRadius)*2 / max(surround.size);
                    m = stage.core.Mask.createCircularAperture(sc);
                    surround.setMask(m);
                else
                    surround.size = obj.canvasSize;
                    surround.position = obj.canvasSize/2;
                end
                p.addStimulus(surround);
                
                % Control when the spot is visible.
                surroundVisible = stage.builtin.controllers.PropertyController(surround, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(surroundVisible);

                % Control the spot color.
                surroundController = stage.builtin.controllers.PropertyController(surround, 'color', ...
                    @(state)getAnnulusAchromatic(obj, state.time - obj.preTime * 1e-3));
                p.addController(surroundController);
            end
            
            if strcmp(obj.stimulusClass, 'spot') || strcmp(obj.stimulusClass, 'center-full') || strcmp(obj.stimulusClass, 'center-surround') || strcmp(obj.stimulusClass,'center-const-surround')
                spot = stage.builtin.stimuli.Ellipse();
                spot.radiusX = obj.radius;
                spot.radiusY = obj.radius; 
                spot.position = obj.canvasSize/2 + obj.centerOffset;
            else
                spot = stage.builtin.stimuli.Rectangle();
                spot.size = obj.canvasSize;
                spot.position = obj.canvasSize/2;
                spot.orientation = 0;
            end
            spot.color = obj.bkg;
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Add a center mask if it's an annulus.
            if strcmp(obj.stimulusClass, 'annulus')
                mask = stage.builtin.stimuli.Ellipse();
                mask.radiusX = obj.apertureRadius;
                mask.radiusY = obj.apertureRadius;
                mask.position = obj.canvasSize/2 + obj.centerOffset;
                mask.color = obj.backgroundIntensity; 
                p.addStimulus(mask);
            end
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            % Control the spot color.
            colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                @(state)getSpotAchromatic(obj, state.time - obj.preTime * 1e-3));
            p.addController(colorController);
            
            function c = getSpotAchromatic(obj, time)
                if time > 0 && time <= obj.stimTime*1e-3
                    c = obj.frameSeq(floor(time*obj.frameRate)+1);
                else
                    c = obj.bkg;
                end
            end
            
            function c = getAnnulusAchromatic(obj, time)
                if time > 0 && time <= obj.stimTime*1e-3
                    c = obj.frameSeqSurround(floor(time*obj.frameRate)+1);
                else
                    c = obj.bkg;
                end
            end
        end
  
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Deal with the seed.
            if obj.randomSeed
                obj.seed = RandStream.shuffleSeed;
            else
                obj.seed = 1;
            end
            
            % Seed the random number generator.
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            % Get the contrast series.
            obj.contrasts = 0.35*obj.noiseStream.rand(1, length(obj.durations));
            
            % Re-seed the random number generator.
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            % Pre-generate frames for the epoch.
            nframes = obj.stimTime*1e-3*obj.frameRate + 15;
            if strcmp(obj.noiseClass,'binary')
                obj.frameSeq = obj.noiseStream.rand(1,nframes) > 0.5;
                obj.frameSeq = 2*obj.frameSeq - 1; 
            else
                obj.frameSeq = 0.3*obj.noiseStream.randn(1,nframes);
            end
            eFrames = cumsum(obj.durations*1e-3*obj.frameRate);
            sFrames = [0 eFrames]+1;
            eFrames(end+1) = nframes;
            
            if strcmp(obj.stimulusClass,'center-const-surround')
                obj.frameSeq = min(obj.contrasts)*obj.frameSeq;
                obj.frameSeqSurround = zeros(size(obj.frameSeq));
                highInd = find(obj.contrasts == max(obj.contrasts),1);
                % Reseed the generator.
                obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed+1);
                obj.frameSeqSurround(sFrames(highInd):eFrames(highInd)) = obj.noiseStream.randn(1,length(sFrames(highInd):eFrames(highInd)));
                if strcmp(obj.noiseClass, 'binary-gaussian') || strcmp(obj.noiseClass, 'binary')
                    obj.frameSeqSurround(obj.frameSeqSurround > 0) = 1;
                    obj.frameSeqSurround(obj.frameSeqSurround < 0) = -1;
                else
                    obj.frameSeqSurround = 0.3*obj.frameSeqSurround;
                end
                obj.frameSeqSurround = max(obj.contrasts)*obj.frameSeqSurround;
                % Convert to LED contrast.
                obj.frameSeq = obj.bkg*obj.frameSeq + obj.bkg;
                obj.frameSeqSurround = obj.bkg*obj.frameSeqSurround + obj.bkg;
            else
                for k = 1 : length(sFrames)
                    if strcmp(obj.noiseClass, 'binary-gaussian')
                        if obj.contrasts(min(k,length(obj.contrasts))) == max(obj.contrasts) && ~isequal(obj.contrasts,obj.contrasts(1)*ones(size(obj.contrasts)))
                            obj.frameSeq(sFrames(k):eFrames(k)) = obj.contrasts(min(k,length(obj.contrasts)))*...
                                (2*(obj.frameSeq(sFrames(k):eFrames(k)) > 0)-1);
                        else
                            obj.frameSeq(sFrames(k):eFrames(k)) = obj.contrasts(min(k,length(obj.contrasts)))*...
                                obj.frameSeq(sFrames(k):eFrames(k));
                        end
                    else
                        obj.frameSeq(sFrames(k):eFrames(k)) = obj.contrasts(min(k,length(obj.contrasts)))*...
                            obj.frameSeq(sFrames(k):eFrames(k));
                    end
                end
                % Convert to LED contrast.
                obj.frameSeq = obj.bkg*obj.frameSeq + obj.bkg;

                if strcmp(obj.stimulusClass, 'center-full') || strcmp(obj.stimulusClass, 'center-surround')
                    obj.frameSeqSurround = ones(size(obj.frameSeq))*obj.bkg;
                    obj.frameSeqSurround(sFrames(2):eFrames(2)) = obj.frameSeq(sFrames(2):eFrames(2));
                    if strcmp(obj.stimulusClass, 'center-surround')
                        obj.frameSeq(sFrames(2):eFrames(2)) = obj.bkg;
                    end
                end
            end
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('contrasts', obj.contrasts);
            epoch.addParameter('durations', obj.durations);
            epoch.addParameter('frameSeq', obj.frameSeq);

            % Add the radius to the epoch.
            if strcmp(obj.stimulusClass, 'annulus')
                epoch.addParameter('outerRadius', min(obj.canvasSize/2));
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