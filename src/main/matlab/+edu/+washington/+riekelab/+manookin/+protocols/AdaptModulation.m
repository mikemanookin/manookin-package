classdef AdaptModulation < edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stim leading duration (ms)
        stimTime = 2000                 % Stim duration (ms)
        tailTime = 250                  % Stim trailing duration (ms)
        highContrasts = [0 1.0]         % High contrast value (0-1)
        highDuration = 1000             % High-contrast duration (ms)
        lowContrasts = [0 0.125 0.25 0.5]       % Low contrast values (0-1)
        temporalFrequencies = [6 6]     % Temporal frequencies (Hz)
        radius = 50                     % Inner radius in pixels.
        apertureRadius = 80             % Blank aperture radius (pix)
        phaseShift = 0.0                % Phase shift (degrees)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        stimulusClass = 'spot'          % Stimulus class
        temporalClass = 'sinewave'      % Temporal class: sinewave or squarewave
        chromaticClass = 'achromatic'   % Chromatic class
        onlineAnalysis = 'extracellular'% Online analysis type.
        numberOfAverages = uint16(64)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave','squarewave'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus', 'full-field','center-surround'})
        bkg
        frameSeq
        frameSeqSurround
        highContrast
        lowContrast
        temporalFrequency
        phaseShiftRad
    end
    
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.manookin.figures.AdaptGratingFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'preTime',obj.preTime,...
                'highTime',obj.highDuration,...
                'numSubplots',length(obj.highContrasts)*max(length(obj.temporalFrequencies),length(obj.lowContrasts)));
            
            if obj.backgroundIntensity == 0
                obj.bkg = 0.5;
            else
                obj.bkg = obj.backgroundIntensity;
            end
            obj.phaseShiftRad = obj.phaseShift / 180 * pi;
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            if strcmp(obj.stimulusClass, 'center-surround')
                surround = stage.builtin.stimuli.Rectangle();
                surround.color = obj.backgroundIntensity;
                surround.position = obj.canvasSize/2 + obj.centerOffset;
                surround.orientation = 0;
                surround.size = max(obj.canvasSize) * ones(1,2) + 2*max(abs(obj.centerOffset));
                sc = (obj.apertureRadius)*2 / max(surround.size);
                m = stage.core.Mask.createCircularAperture(sc);
                surround.setMask(m);
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
            
            if strcmp(obj.stimulusClass, 'spot') || strcmp(obj.stimulusClass, 'center-surround')
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
            
            % Deal with epoch-specific parameters.
            obj.temporalFrequency = obj.temporalFrequencies(mod(obj.numEpochsCompleted,length(obj.temporalFrequencies))+1);
            obj.highContrast = obj.highContrasts(mod(obj.numEpochsCompleted,length(obj.highContrasts))+1);
            obj.lowContrast = obj.lowContrasts(mod(floor(obj.numEpochsCompleted/length(obj.highContrasts)),length(obj.lowContrasts))+1);
            
            % Calculate the number of high contrast frames.
            highFrames = floor(obj.highDuration*1e-3*obj.frameRate*0.9985);
            
            % Pre-generate frames for the epoch.
            nframes = ceil(obj.stimTime*1e-3*obj.frameRate*0.9985) + 15;
            % Generate the sinusoidal modulation
            obj.frameSeq = sin((0:nframes-1)/obj.frameRate*0.9985*2*pi*obj.temporalFrequency);
            
            % Deal with the phase shift after transition.
            obj.frameSeq(highFrames+1:end) = sin((highFrames:nframes-1)/obj.frameRate*0.9985*2*pi*obj.temporalFrequency + obj.phaseShiftRad);
            
            obj.frameSeq = obj.frameSeq / max(obj.frameSeq);
            if strcmp(obj.temporalClass, 'squarewave')
                obj.frameSeq = sign(obj.frameSeq);
            end
            
            obj.frameSeq(1:highFrames) = obj.frameSeq(1:highFrames)*obj.highContrast;
            obj.frameSeq(highFrames+1:end) = obj.frameSeq(highFrames+1:end)*obj.lowContrast;
            
            % Convert to LED contrast.
            obj.frameSeq = obj.bkg*obj.frameSeq + obj.bkg;
            
            if strcmp(obj.stimulusClass, 'center-surround')
                obj.frameSeqSurround = ones(size(obj.frameSeq))*obj.bkg;
                obj.frameSeqSurround(1:highFrames) = obj.frameSeq(1:highFrames);
                obj.frameSeq(1:highFrames) = obj.bkg;
            end
            
            % Save the seed.
            epoch.addParameter('highContrast', obj.highContrast);
            epoch.addParameter('lowContrast', obj.lowContrast);
            epoch.addParameter('temporalFrequency',obj.temporalFrequency);
            epoch.addParameter('epochTag',['hiCt',num2str(obj.highContrast),'lowCt',num2str(obj.lowContrast),'tF',num2str(obj.temporalFrequency)]);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
    end
    
end