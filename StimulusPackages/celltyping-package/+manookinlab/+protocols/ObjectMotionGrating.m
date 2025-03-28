classdef ObjectMotionGrating < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Grating leading duration (ms)
        stimTime = 6000                 % Grating duration (ms)
        tailTime = 500                  % Grating trailing duration (ms)
        contrast = 0.5                  % Grating contrast (0-1)
        orientation = 0.0               % Grating orientation (deg)
        barWidth = 50                   % Bar width (microns)
        jitterSpeed = 1000              % Grating jitter/frame (pix/sec)
        driftSpeed = 1000               % Center drift speed (pix/sec)
        spatialPhase = 0.0              % Spatial phase of grating (deg)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        innerRadius = 200               % Center radius (in microns).
        apertureRadius = 250            % Aperature radius between inner and outer gratings (microns).
        spatialClass = 'squarewave'     % Spatial type (sinewave or squarewave)      
        onlineAnalysis = 'extracellular' % Type of online analysis
        useRandomSeed = false            % Random or repeated seed?
        numberOfAverages = uint16(24)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'drifting', 'reversing'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stimulusClasses = {'eye+object','eye','object','eye+object drift'}
        stimulusClass
        spatialFrequency
        driftStep
        phaseShift
        seed
        noiseStream
        noiseStream2
        stepSize
        centerPhase
        surroundPhase
        barWidthPix
        jitterSpeedPix
        driftSpeedPix 
        innerRadiusPix 
        apertureRadiusPix
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
                colors = [0 0 0; 0.8 0 0; 0 0.7 0.2; 0 0.2 1];
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',colors,...
                    'groupBy',{'stimulusClass'});
            end
            
            obj.barWidthPix = obj.rig.getDevice('Stage').um2pix(obj.barWidth);
            obj.jitterSpeedPix = obj.rig.getDevice('Stage').um2pix(obj.jitterSpeed);
            obj.driftSpeedPix = obj.rig.getDevice('Stage').um2pix(obj.driftSpeed);
            obj.innerRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.innerRadius);
            obj.apertureRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.apertureRadius);
            
            obj.stepSize = obj.jitterSpeedPix / obj.frameRate;
            obj.driftStep = obj.driftSpeedPix / obj.frameRate;
        end
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            obj.centerPhase = 0;
            obj.surroundPhase = 0;
            % Create the background grating.
            if ~strcmp(obj.stimulusClass, 'object')
                switch obj.spatialClass
                    case 'sinewave'
                        bGrating = stage.builtin.stimuli.Grating('sine');
                    otherwise % Square-wave grating
                        bGrating = stage.builtin.stimuli.Grating('square'); 
                end
                bGrating.orientation = obj.orientation;
                bGrating.size = max(obj.canvasSize) * ones(1,2);
                bGrating.position = obj.canvasSize/2;
                bGrating.spatialFreq = 1/(2*obj.barWidthPix); %convert from bar width to spatial freq
                bGrating.contrast = obj.contrast;
                bGrating.color = 2*obj.backgroundIntensity;
            end
            
            % Create the grating.
            switch obj.spatialClass
                case 'sinewave'
                    grate = stage.builtin.stimuli.Grating('sine');
                otherwise % Square-wave grating
                    grate = stage.builtin.stimuli.Grating('square'); 
            end
            grate.orientation = obj.orientation;
            grate.size = 2*obj.innerRadiusPix*ones(1,2);
            grate.position = obj.canvasSize/2;
            grate.spatialFreq = 1/(2*obj.barWidthPix); %convert from bar width to spatial freq
            grate.contrast = obj.contrast;
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
            grate.phase = obj.phaseShift + obj.spatialPhase; %keep contrast reversing boundary in center
            % Make a circular mask.
%             gMask = stage.core.Mask.createCircularAperture(obj.innerRadiusPix*2/max(obj.canvasSize), 1024);
            gMask = stage.core.Mask.createCircularEnvelope(1024);
            grate.setMask(gMask);
            
            if ~strcmp(obj.stimulusClass, 'object')
                bGrating.phase = obj.phaseShift + obj.spatialPhase; 
                p.addStimulus(bGrating);
                
                % Make the grating visible only during the stimulus time.
                grate2Visible = stage.builtin.controllers.PropertyController(bGrating, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(grate2Visible);
                
                bgController = stage.builtin.controllers.PropertyController(bGrating, 'phase',...
                    @(state)surroundTrajectory(obj, state.time - obj.preTime * 1e-3));
                p.addController(bgController);
            end
            
            if obj.apertureRadiusPix > obj.innerRadiusPix
                mask = stage.builtin.stimuli.Ellipse();
                mask.color = obj.backgroundIntensity;
                mask.radiusX = obj.apertureRadiusPix;
                mask.radiusY = obj.apertureRadiusPix;
                mask.position = obj.canvasSize / 2;
                p.addStimulus(mask);
            end
            
            % Add the grating.
            p.addStimulus(grate);
            
            % Make the grating visible only during the stimulus time.
            grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(grateVisible);
            
            %--------------------------------------------------------------
            % Control the grating phase.
            
            %{'eye+object','eye','object','eye+object drift'}
            switch obj.stimulusClass
                case 'eye+object drift'
                    imgController = stage.builtin.controllers.PropertyController(grate, 'phase',...
                        @(state)objectDriftTrajectory(obj, state.time - obj.preTime * 1e-3));
                otherwise
                    imgController = stage.builtin.controllers.PropertyController(grate, 'phase',...
                        @(state)objectTrajectory(obj, state.time - obj.preTime * 1e-3));
            end
            p.addController(imgController);
            
            % Object/center trajectory.
            function p = objectTrajectory(obj, time)
                if time > 0
                    p = obj.noiseStream.randn*2*pi * obj.stepSize / obj.barWidthPix;
                else
                    p = 0;
                end
                obj.centerPhase = obj.centerPhase + p;
                p = obj.centerPhase*180/pi + obj.phaseShift + obj.spatialPhase;
            end
            
            % Set the drifting grating.
            function phase = objectDriftTrajectory(obj, time)
                if time >= 0
                    phase = (obj.driftStep/obj.barWidthPix * 2 * pi)+(obj.noiseStream.randn*2*pi * obj.stepSize / obj.barWidthPix);
                else
                    phase = 0;
                end
                obj.centerPhase = obj.centerPhase + phase;
                phase = obj.centerPhase*180/pi + obj.phaseShift + obj.spatialPhase;
            end
            
            % Surround trajectory
            function p = surroundTrajectory(obj, time)
                if time > 0
                    p = obj.noiseStream2.randn*2*pi * obj.stepSize / obj.barWidthPix;
                else
                    p = 0;
                end
                obj.surroundPhase = obj.surroundPhase + p;
                p = obj.surroundPhase*180/pi + obj.phaseShift + obj.spatialPhase;
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.stimulusClass = obj.stimulusClasses{mod(obj.numEpochsCompleted,length(obj.stimulusClasses))+1};
            epoch.addParameter('stimulusClass', obj.stimulusClass);
            
            % Deal with the seed.
            if obj.useRandomSeed
                obj.seed = RandStream.shuffleSeed;
            else
                obj.seed = 0;
            end
            if strcmp(obj.stimulusClass,'eye+object')
                seed2 = obj.seed + 1781;
            else
                seed2 = obj.seed;
            end
            epoch.addParameter('surroundSeed', seed2);
            
            % Set the noise streams.
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.noiseStream2 = RandStream('mt19937ar', 'Seed', seed2);
            
            % Get the spatial frequency.
            obj.spatialFrequency = 1/(2*obj.barWidthPix);

            % Add the spatial frequency to the epoch.
            epoch.addParameter('spatialFrequency', obj.spatialFrequency);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end 