classdef AdaptGrating < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stim leading duration (ms)
        stimTime = 4000                 % Stim duration (ms)
        tailTime = 250                  % Stim trailing duration (ms)
        lowContrast = 0.0               % Low-contrast value (0-1)
        highContrast = 1.0              % High-contrast value (0-1)
        highDuration = 2000             % High-contrast duration (ms)
        barWidths = [40 400]            % Bar widths (pix)
        temporalFrequencies = [6 6] % Temporal frequencies (Hz)
        orientation = 0                 % Stimulus orientiation (degrees)
        spatialPhase = 0.0              % Spatial phase of grating (deg)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        apertureRadius = 1000            % Aperture radius in pixels.
        apertureClass = 'spot'          % Spot or annulus?       
        spatialClass = 'sinewave'       % Spatial type (sinewave or squarewave)
        temporalClass = 'drifting'      % Temporal type (drifting or reversing) 
        onlineAnalysis = 'extracellular'% Online analysis type.
        numberOfAverages = uint16(18)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        apertureClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'drifting', 'reversing'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        barWidth
        temporalFrequency
        spatialFrequency
        phaseShift
        highTime
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.AdaptGratingFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'preTime',obj.preTime,...
                'highTime',obj.highDuration,...
                'numSubplots',max(length(obj.temporalFrequencies),length(obj.barWidths)));
            
            obj.highTime = obj.highDuration*1e-3;
        end
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Create the grating.
            switch obj.spatialClass
                case 'sinewave'
                    grate = stage.builtin.stimuli.Grating('sine');
                otherwise % Square-wave grating
                    grate = stage.builtin.stimuli.Grating('square'); 
            end
            grate.orientation = obj.orientation;
            if obj.apertureRadius > 0 && obj.apertureRadius < max(obj.canvasSize/2)
                grate.size = 2*obj.apertureRadius*ones(1,2);
            else
                grate.size = max(obj.canvasSize) * ones(1,2);
            end
            grate.position = obj.canvasSize/2 + obj.centerOffset;
            grate.spatialFreq = 1/(2*obj.barWidth); %convert from bar width to spatial freq
            grate.contrast = obj.highContrast;
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
            
            % Add the grating.
            p.addStimulus(grate);
            
            % Make the grating visible only during the stimulus time.
            grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(grateVisible);
            
            %--------------------------------------------------------------
            % Control the grating phase.
            if strcmp(obj.temporalClass, 'drifting')
                imgController = stage.builtin.controllers.PropertyController(grate, 'phase',...
                    @(state)setDriftingGrating(obj, state.time - obj.preTime * 1e-3));
            else
                imgController = stage.builtin.controllers.PropertyController(grate, 'phase',...
                    @(state)setReversingGrating(obj, state.time - obj.preTime * 1e-3));
            end
            p.addController(imgController);
            
            % Set the drifting grating.
            function phase = setDriftingGrating(obj, time)
                if time >= 0
                    phase = obj.temporalFrequency * time * 2 * pi;
                else
                    phase = 0;
                end
                
                phase = phase*180/pi + obj.phaseShift + obj.spatialPhase;
            end
            
            % Set the reversing grating
            function phase = setReversingGrating(obj, time)
                if time >= 0
                    phase = round(0.5 * sin(time * 2 * pi * obj.temporalFrequency) + 0.5) * pi;
                else
                    phase = 0;
                end
                
                phase = phase*180/pi + obj.phaseShift + obj.spatialPhase;
            end
            
            % Control the contrast.
            ctController = stage.builtin.controllers.PropertyController(grate, 'contrast',...
                @(state)setContrast(obj, state.time - obj.preTime * 1e-3));
            p.addController(ctController);
            
            function c = setContrast(obj, time)
                if time <= obj.highTime
                    c = obj.highContrast;
                else
                    c = obj.lowContrast;
                end
            end

            if obj.apertureRadius > 0
                if strcmpi(obj.apertureClass, 'spot')
                    aperture = stage.builtin.stimuli.Rectangle();
                    aperture.position = obj.canvasSize/2 + obj.centerOffset;
                    aperture.color = obj.backgroundIntensity;
                    aperture.size = [max(obj.canvasSize) max(obj.canvasSize)];
                    mask = stage.core.Mask.createCircularAperture(obj.apertureRadius*2/max(obj.canvasSize), 1024);
                    aperture.setMask(mask);
                    p.addStimulus(aperture);
                else
                    mask = stage.builtin.stimuli.Ellipse();
                    mask.color = obj.backgroundIntensity;
                    mask.radiusX = obj.apertureRadius;
                    mask.radiusY = obj.apertureRadius;
                    mask.position = obj.canvasSize / 2 + obj.centerOffset;
                    p.addStimulus(mask);
                end
            end
        end
  
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Set the current bar width.
            obj.barWidth = obj.barWidths( mod(obj.numEpochsCompleted,length(obj.barWidths))+1 );
            % Set the current temporal frequency
            obj.temporalFrequency = obj.temporalFrequencies( mod(obj.numEpochsCompleted,length(obj.temporalFrequencies))+1 );
            
            % Get the spatial frequency.
            obj.spatialFrequency = 1/(2*obj.barWidth);

            % Add the spatial frequency to the epoch.
            epoch.addParameter('spatialFrequency', obj.spatialFrequency);
            
            % Save out the current bar width.
            epoch.addParameter('barWidth', obj.barWidth);
            epoch.addParameter('temporalFrequency',obj.temporalFrequency);
            epoch.addParameter('epochTag',['barWidth',num2str(obj.barWidth),'-tFreq',num2str(obj.temporalFrequency)]);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
    end
    
end