classdef GratingMTF < edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Grating leading duration (ms)
        stimTime = 2500                 % Grating duration (ms)
        tailTime = 250                  % Grating trailing duration (ms)
        waitTime = 0                    % Grating wait duration (ms)
        contrast = 1.0                  % Grating contrast (0-1)
        orientation = 0.0               % Grating orientation (deg)
        barWidths = [900:-100:300 250:-50:100 75:-25:25 20:-5:5] % Bar widths (pixels)
        temporalFrequency = 2.0         % Temporal frequency (Hz)
        spatialPhase = 0.0              % Spatial phase of grating (deg)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        apertureRadius = 0              % Aperture radius in pixels.
        apertureClass = 'spot'          % Spot or annulus?       
        spatialClass = 'sinewave'       % Spatial type (sinewave or squarewave)
        temporalClass = 'drifting'      % Temporal type (drifting or reversing)      
        onlineAnalysis = 'extracellular'         % Type of online analysis
        numberOfAverages = uint16(18)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        apertureClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'drifting', 'reversing'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        spatialFrequency
        barWidth
        widths
        phaseShift
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('edu.washington.riekelab.manookin.figures.sMTFFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                    'temporalType', obj.temporalClass, 'spatialType', 'spot', ...
                    'xName', 'barWidth', 'xaxis', unique(obj.barWidths), ...
                    'temporalFrequency', obj.temporalFrequency);
            end
            
            % Organize stimulus and analysis parameters.
            obj.organizeParameters();
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
            if obj.apertureRadius > 0 && obj.apertureRadius < max(obj.canvasSize/2) && strcmpi(obj.apertureClass, 'spot')
                grate.size = 2*obj.apertureRadius*ones(1,2);
            else
                grate.size = max(obj.canvasSize) * ones(1,2);
            end
            grate.position = obj.canvasSize/2 + obj.centerOffset;
            grate.spatialFreq = 1/(2*obj.barWidth); %convert from bar width to spatial freq
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
                    @(state)setDriftingGrating(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
            else
                imgController = stage.builtin.controllers.PropertyController(grate, 'phase',...
                    @(state)setReversingGrating(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
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
            
%             if (obj.temporalFrequency > 0) 
%                 grateContrast = stage.builtin.controllers.PropertyController(grate, 'contrast',...
%                     @(state)getGrateContrast(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
%                 p.addController(grateContrast); %add the controller
%             end
%             function c = getGrateContrast(obj, time)
%                 if time > 0
%                     c = obj.contrast.*sin(2 * pi * obj.temporalFrequency * time);
%                 else
%                     c = 0;
%                 end
%             end

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
        
        % This is a method of organizing stimulus parameters.
        function organizeParameters(obj)
            
            % Create the matrix of bar positions.
            numReps = ceil(double(obj.numberOfAverages) / length(obj.barWidths));
            
            % Get the array of radii.
            freqs = obj.barWidths(:) * ones(1, numReps);
            freqs = freqs(:)';
            
            % Copy to spatial frequencies.
            obj.widths = freqs;
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Set the current bar width.
            obj.barWidth = obj.widths( obj.numEpochsCompleted+1 );
            
            % Get the spatial frequency.
            obj.spatialFrequency = 1/(2*obj.barWidth);

            % Add the spatial frequency to the epoch.
            epoch.addParameter('spatialFrequency', obj.spatialFrequency);
            
            % Save out the current bar width.
            epoch.addParameter('barWidth', obj.barWidth);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end 