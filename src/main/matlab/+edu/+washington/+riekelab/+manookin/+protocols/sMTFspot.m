classdef sMTFspot < edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 500                   % Spot leading duration (ms)
        stimTime = 2500                 % Spot duration (ms)
        tailTime = 500                  % Spot trailing duration (ms)
        contrast = 0.5                  % Contrast (0-1; -1-1 for pulse)
        temporalFrequency = 2.0         % Modulation frequency (Hz)
        radii = round(17.9596 * 10.^(-0.301:0.301/3:1.4047)) % Inner radius in pixels.
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        temporalClass = 'sinewave'      % Sinewave or squarewave?
        chromaticClass = 'achromatic'   % Spot color
        stimulusClass = 'spot'          % Stimulus class
        onlineAnalysis = 'extracellular' % Online analysis type.
        numberOfAverages = uint16(18)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave', 'pulse'})
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic', 'red', 'green', 'blue', 'yellow', 'L-iso', 'M-iso', 'S-iso', 'LM-iso'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus'})
        currentRadius
        sequence
        bkg
    end
    
     % Analysis properties
    properties (Hidden)
        xaxis
        F1Amp
        F1Phase
        repsPerX
    end
    
    properties (Hidden, Transient)
        analysisFigure
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
                    'temporalType', obj.temporalClass, 'spatialType', obj.stimulusClass, ...
                    'xName', 'radius', 'xaxis', unique(obj.radii), ...
                    'temporalFrequency', obj.temporalFrequency);
            end
            
%             if ~strcmp(obj.onlineAnalysis, 'none')
%                 obj.analysisFigure = obj.showFigure('symphonyui.builtin.figures.CustomFigure', @obj.MTFanalysis);
%                 f = obj.analysisFigure.getFigureHandle();
%                 set(f, 'Name', 'spatial MTF');
%                 obj.analysisFigure.userData.axesHandle = axes('Parent', f);
%             end
            
            if obj.backgroundIntensity == 0
                obj.bkg = 0.5;
            else
                obj.bkg = obj.backgroundIntensity;
            end
            
            if strcmp(obj.stageClass, 'LightCrafter')
                obj.chromaticClass = 'achromatic';
            end
            
            obj.organizeParameters();
            
            obj.setColorWeights();
        end
        
        function MTFanalysis(obj, ~, epoch)
            response = epoch.getResponse(obj.rig.getDevice(obj.amp));
            responseTrace = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            
            % Analyze response by type.
            responseTrace = obj.getResponseByType(responseTrace, obj.onlineAnalysis);
            
            %--------------------------------------------------------------
            % Get the F1 amplitude and phase.
            responseTrace = responseTrace(obj.preTime/1000*sampleRate+1 : end);
            binRate = 60;
            binWidth = sampleRate / binRate; % Bin at 60 Hz.
            numBins = floor(obj.stimTime/1000 * binRate);
            binData = zeros(1, numBins);
            for k = 1 : numBins
                index = round((k-1)*binWidth+1 : k*binWidth);
                binData(k) = mean(responseTrace(index));
            end
            binsPerCycle = binRate / obj.temporalFrequency;
            numCycles = floor(length(binData)/binsPerCycle);
            cycleData = zeros(1, floor(binsPerCycle));
            for k = 1 : numCycles
                index = round((k-1)*binsPerCycle) + (1 : floor(binsPerCycle));
                cycleData = cycleData + binData(index);
            end
            cycleData = cycleData / k;
            
            ft = fft(cycleData);
            
            index = find(obj.xaxis == obj.currentRadius, 1);
            obj.F1Amp(index) = abs(ft(2)) / length(ft)*2;
            obj.F1Phase(index) = angle(ft(2)) * 180 / pi;
            %--------------------------------------------------------------
            
            axesHandle = obj.analysisFigure.userData.axesHandle;
            cla(axesHandle);
            
%             h1 = subplot(3,1,1:2, axesHandle);
            h1 = axesHandle;
            plot(obj.xaxis, obj.F1Amp, 'ko-', 'Parent', h1);
            set(h1, 'TickDir', 'out');
            ylabel(h1, 'F1 amp');
            title(['Epoch ', num2str(obj.numEpochsCompleted), ' of ', num2str(obj.numberOfAverages)], 'Parent', h1);
            
%             h2 = subplot(3,1,3, axesHandle);
%             plot(obj.xaxis, obj.F1Phase, 'ko-', 'Parent', h2);
%             set(h2, 'TickDir', 'out');
%             xlabel(h2, 'radius (pix)'); ylabel(h2, 'F1 phase');
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            spot = stage.builtin.stimuli.Ellipse();
            if strcmp(obj.stimulusClass, 'annulus')
                spot.radiusX = min(obj.canvasSize/2);
                spot.radiusY = min(obj.canvasSize/2);
            else
                spot.radiusX = obj.currentRadius;
                spot.radiusY = obj.currentRadius;
            end
            spot.position = obj.canvasSize/2 + obj.centerOffset;
            if strcmp(obj.stageClass, 'Video')
                spot.color = obj.contrast*obj.colorWeights*obj.bkg + obj.bkg;
            else
                spot.color = obj.colorWeights(1)*obj.contrast*obj.bkg + obj.bkg;
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Add an center mask if it's an annulus.
            if strcmp(obj.stimulusClass, 'annulus')
                mask = stage.builtin.stimuli.Ellipse();
                mask.radiusX = obj.currentRadius;
                mask.radiusY = obj.currentRadius;
                mask.position = obj.canvasSize/2 + obj.centerOffset;
                mask.color = obj.backgroundIntensity; 
                p.addStimulus(mask);
            end
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            % Control the spot color.
            if strcmp(obj.stageClass, 'LcrRGB')
                if strcmp(obj.temporalClass, 'sinewave')
                    colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                    @(state)getSpotColorLcrRGB(obj, state));
                p.addController(colorController);
                elseif strcmp(obj.temporalClass, 'squarewave')
                    colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                    @(state)getSpotColorLcrRGBSqwv(obj, state));
                p.addController(colorController);
                end
            elseif strcmp(obj.stageClass, 'Video') && ~strcmp(obj.chromaticClass, 'achromatic')
                if strcmp(obj.temporalClass, 'sinewave')
                    colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                        @(state)getSpotColorVideo(obj, state.time - obj.preTime * 1e-3));
                    p.addController(colorController);
                elseif strcmp(obj.temporalClass, 'squarewave')
                    colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                        @(state)getSpotColorVideoSqwv(obj, state.time - obj.preTime * 1e-3));
                    p.addController(colorController);
                end
            else
                if strcmp(obj.temporalClass, 'sinewave')
                    colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                        @(state)getSpotAchromatic(obj, state.time - obj.preTime * 1e-3));
                    p.addController(colorController);
                elseif strcmp(obj.temporalClass, 'squarewave')
                    colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                        @(state)getSpotAchromaticSqwv(obj, state.time - obj.preTime * 1e-3));
                    p.addController(colorController);
                end
            end
            
            function c = getSpotColorVideo(obj, time)
                c = obj.contrast * obj.colorWeights * sin(obj.temporalFrequency*time*2*pi) * obj.bkg + obj.bkg;
            end
            
            function c = getSpotColorVideoSqwv(obj, time)
                c = obj.contrast * obj.colorWeights * sign(sin(obj.temporalFrequency*time*2*pi)) * obj.bkg + obj.bkg;
            end
            
            function c = getSpotAchromatic(obj, time)
                c = obj.contrast * sin(obj.temporalFrequency*time*2*pi) * obj.bkg + obj.bkg;
            end
            
            function c = getSpotAchromaticSqwv(obj, time)
                c = obj.contrast * sign(sin(obj.temporalFrequency*time*2*pi)) * obj.bkg + obj.bkg;
            end
            
            function c = getSpotColorLcrRGB(obj, state)
                if state.pattern == 0
                    c = obj.contrast * obj.colorWeights(1) * sin(obj.temporalFrequency*(state.time - obj.preTime * 1e-3)*2*pi) * obj.bkg + obj.bkg;
                elseif state.pattern == 1
                    c = obj.contrast * obj.colorWeights(2) * sin(obj.temporalFrequency*(state.time - obj.preTime * 1e-3)*2*pi) * obj.bkg + obj.bkg;
                else
                    c = obj.contrast * obj.colorWeights(3) * sin(obj.temporalFrequency*(state.time - obj.preTime * 1e-3)*2*pi) * obj.bkg + obj.bkg;
                end
            end
            
            function c = getSpotColorLcrRGBSqwv(obj, state)
                if state.pattern == 0
                    c = obj.contrast * obj.colorWeights(1) * sign(sin(obj.temporalFrequency*(state.time - obj.preTime * 1e-3)*2*pi)) * obj.bkg + obj.bkg;
                elseif state.pattern == 1
                    c = obj.contrast * obj.colorWeights(2) * sign(sin(obj.temporalFrequency*(state.time - obj.preTime * 1e-3)*2*pi)) * obj.bkg + obj.bkg;
                else
                    c = obj.contrast * obj.colorWeights(3) * sign(sin(obj.temporalFrequency*(state.time - obj.preTime * 1e-3)*2*pi)) * obj.bkg + obj.bkg;
                end
            end
        end
        
        % This is a method of organizing stimulus parameters.
        function organizeParameters(obj)
            
            % Create the matrix of bar positions.
            numReps = ceil(double(obj.numberOfAverages) / length(obj.radii));
            
            % Get the array of radii.
            rads = obj.radii(:) * ones(1, numReps);
            rads = rads(:)';
            
            % Copy the radii in the correct order.
            rads = rads( 1 : obj.numberOfAverages );
            
            % Copy to spatial frequencies.
            obj.sequence = rads;
            
            obj.xaxis = unique(obj.radii);
            obj.F1Amp = zeros(size(obj.xaxis));
            obj.F1Phase = zeros(size(obj.xaxis));
            obj.repsPerX = zeros(size(obj.xaxis));
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj, epoch);
            
%             device = obj.rig.getDevice(obj.amp);
%             duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
%             epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
%             epoch.addResponse(device);
            
            % Set the current radius
            obj.currentRadius = obj.sequence( obj.numEpochsCompleted+1 );

            % Add the radius to the epoch.
            if strcmp(obj.stimulusClass, 'annulus')
                epoch.addParameter('outerRadius', min(obj.canvasSize/2));
            end
            epoch.addParameter('radius', obj.currentRadius);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
    end
end