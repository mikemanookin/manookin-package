classdef ContrastResponseGrating < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Grating leading duration (ms)
        stimTime = 3500                 % Grating duration (ms)
        tailTime = 250                  % Grating trailing duration (ms)
        contrasts = [0 0.01 0.02 0.04 0.04 0.08 0.08 0.16 0.16 0.32 0.64 0.96] % Grating contrast (0-1)
        orientation = 0.0               % Grating orientation (deg)
        barWidth = 250                  % Grating bar width (pix)
        temporalFrequency = 2.0         % Temporal frequency (Hz)
        spatialPhase = 0.0              % Spatial phase of grating (deg)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        apertureRadius = 0              % Aperture radius in pixels.
        apertureClass = 'spot'          % Spot or annulus?       
        spatialClass = 'squarewave'     % Spatial type (sinewave or squarewave)
        temporalClass = 'drifting'      % Temporal type (drifting or reversing)      
        chromaticClass = 'achromatic'   % Chromatic type
        onlineAnalysis = 'extracellular'% Type of online analysis
        numberOfAverages = uint16(12)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        apertureClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'drifting', 'reversing'})
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','red-green isoluminant','red-green isochromatic','S-iso','M-iso','L-iso'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        rawImage
        spatialPhaseRad % The spatial phase in radians.
        contrast
        spatialFreq % The current spatial frequency for the epoch
        backgroundMeans
    end
    
    % Analysis properties
    properties (Hidden)
        xaxis
        F1Amp
        repsPerX
        coneContrasts 
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
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            obj.showFigure('manookinlab.figures.ContrastResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'preTime',obj.preTime,...
                'stimTime',obj.stimTime,...
                'contrasts',unique(obj.contrasts),...
                'temporalClass','drifting',...
                'temporalFrequency',obj.temporalFrequency);
            
%             if ~strcmp(obj.onlineAnalysis, 'none')
%                 obj.analysisFigure = obj.showFigure('symphonyui.builtin.figures.CustomFigure', @obj.CRFanalysis);
%                 f = obj.analysisFigure.getFigureHandle();
%                 set(f, 'Name', 'Contrast Response Function');
%                 obj.analysisFigure.userData.axesHandle = axes('Parent', f);
%             end
            
            % Calculate the spatial phase in radians.
            obj.spatialPhaseRad = obj.spatialPhase / 180 * pi;
            % Calculate the spatial frequency.
            obj.spatialFreq = min(obj.canvasSize)/(2*obj.barWidth);
            
            % Set the LED weights.
            if strcmp(obj.stageClass,'LightCrafter')
                obj.backgroundMeans = obj.backgroundIntensity*ones(1,3);
                obj.colorWeights = ones(1,3);
            else
                if strcmp(obj.chromaticClass, 'achromatic')
                    obj.backgroundMeans = obj.backgroundIntensity*ones(1,3);
                    obj.colorWeights = ones(1,3);
                else
                    [obj.backgroundMeans, ~, obj.colorWeights] = getMaxContrast(obj.quantalCatch, obj.chromaticClass);
                end
            end
            
            % Calculate the cone contrasts.
            obj.coneContrasts = coneContrast((obj.backgroundMeans(:)*ones(1,size(obj.quantalCatch,2))).*obj.quantalCatch, ...
                obj.colorWeights, 'michaelson');
            
            % Set up the raw image.
            obj.setRawImage();
            
            obj.xaxis = unique(obj.contrasts);
            obj.F1Amp = zeros(size(obj.xaxis));
            obj.repsPerX = zeros(size(obj.xaxis));
        end
        
        function CRFanalysis(obj, ~, epoch)
            response = epoch.getResponse(obj.rig.getDevice(obj.amp));
            [y, ~] = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            
            prePts = round(obj.preTime/1000*sampleRate);
            
            binRate = 60;
            if strcmp(obj.onlineAnalysis,'extracellular')
                res = spikeDetectorOnline(y,[],sampleRate);
                y = zeros(size(y));
                y(res.sp) = sampleRate; %spike binary
            else
                if prePts > 0
                    y = y - median(y(1:prePts));
                else
                    y = y - median(y);
                end
            end
            
            %--------------------------------------------------------------
            % Get the F1 amplitude and phase.
            responseTrace = y(obj.preTime/1000*sampleRate+1 : end);
            
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
            
            index = find(obj.xaxis == obj.contrast, 1);
            r = obj.F1Amp(index) * obj.repsPerX(index);
            r = r + abs(ft(2))/length(ft)*2;
            
            % Increment the count.
            obj.repsPerX(index) = obj.repsPerX(index) + 1;
            obj.F1Amp(index) = r / obj.repsPerX(index);
            %--------------------------------------------------------------
            
            axesHandle = obj.analysisFigure.userData.axesHandle;
            cla(axesHandle);
            
            h1 = axesHandle;
            plot(obj.xaxis, obj.F1Amp, 'ko-', 'Parent', h1);
            set(h1, 'TickDir', 'out');
            ylabel(h1, 'F1 amp');
            title(['Epoch ', num2str(obj.numEpochsCompleted), ' of ', num2str(obj.numberOfAverages)], 'Parent', h1);
        end
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundMeans); % Set background intensity
            
            % Create the grating.
            grate = stage.builtin.stimuli.Image(uint8(0 * obj.rawImage));
            grate.position = obj.canvasSize / 2;
            grate.size = ceil(sqrt(obj.canvasSize(1)^2 + obj.canvasSize(2)^2))*ones(1,2);
            grate.orientation = obj.orientation;
            
            % Set the minifying and magnifying functions.
            grate.setMinFunction(GL.NEAREST);
            grate.setMagFunction(GL.NEAREST);
            
            % Add the grating.
            p.addStimulus(grate);
            
            % Make the grating visible only during the stimulus time.
            grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(grateVisible);
            
            %--------------------------------------------------------------
            % Generate the grating.
            if strcmp(obj.temporalClass, 'drifting')
                imgController = stage.builtin.controllers.PropertyController(grate, 'imageMatrix',...
                    @(state)setDriftingGrating(obj, state.time - obj.preTime * 1e-3));
            else
                imgController = stage.builtin.controllers.PropertyController(grate, 'imageMatrix',...
                    @(state)setReversingGrating(obj, state.time - obj.preTime * 1e-3));
            end
            p.addController(imgController);
            
            % Set the drifting grating.
            function g = setDriftingGrating(obj, time)
                if time >= 0
                    phase = obj.temporalFrequency * time * 2 * pi;
                else
                    phase = 0;
                end
                
                g = cos(obj.spatialPhaseRad + phase + obj.rawImage);
                
                if strcmp(obj.spatialClass, 'squarewave')
                    g = sign(g);
                end
                
                g = obj.contrast * g;
                
                % Deal with chromatic gratings.
                if ~strcmp(obj.stageClass,'LightCrafter')
                    for m = 1 : 3
                        g(:,:,m) = obj.backgroundMeans(m) * obj.colorWeights(m) * g(:,:,m) + obj.backgroundMeans(m);
                    end
                    g = uint8(255*(g));
                else
                    g = uint8(255*(obj.backgroundIntensity * g + obj.backgroundIntensity));
                end
            end
            
            % Set the reversing grating
            function g = setReversingGrating(obj, time)
                if time >= 0
                    phase = round(0.5 * sin(time * 2 * pi * obj.temporalFrequency) + 0.5) * pi;
                else
                    phase = 0;
                end
                
                g = cos(obj.spatialPhaseRad + phase + obj.rawImage);
                
                if strcmp(obj.spatialClass, 'squarewave')
                    g = sign(g);
                end
                
                g = obj.contrast * g;
                
                % Deal with chromatic gratings.
                if ~strcmp(obj.chromaticClass, 'achromatic')
                    for m = 1 : 3
                        g(:,:,m) = obj.colorWeights(m) * g(:,:,m);
                    end
                end
                g = uint8(255*(obj.backgroundIntensity * g + obj.backgroundIntensity));
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
        
        function setRawImage(obj)
            downsamp = 3;
            sz = ceil(sqrt(obj.canvasSize(1)^2 + obj.canvasSize(2)^2));
            [x,y] = meshgrid(...
                linspace(-sz/2, sz/2, sz/downsamp), ...
                linspace(-sz/2, sz/2, sz/downsamp));
            
            % Calculate the orientation in radians.
            rotRads = obj.orientation / 180 * pi;
            
            % Center the stimulus.
            x = x + obj.centerOffset(1)*cos(rotRads);
            y = y + obj.centerOffset(2)*sin(rotRads);
            
            x = x / min(obj.canvasSize) * 2 * pi;
            y = y / min(obj.canvasSize) * 2 * pi;
            
            % Calculate the raw grating image.
            img = (cos(0)*x + sin(0) * y) * obj.spatialFreq;
            obj.rawImage = img(1,:);
%             obj.rawImage = (cos(rotRads) * x + sin(rotRads) * y) * obj.spatialFreq;
            
            if ~strcmp(obj.stageClass, 'LightCrafter')
                obj.rawImage = repmat(obj.rawImage, [1 1 3]);
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);

            % Set the current spatial frequency.
            obj.contrast = obj.contrasts( mod(obj.numEpochsCompleted,length(obj.contrasts))+1 );

            % Add the spatial frequency to the epoch.
            epoch.addParameter('contrast', obj.contrast);
            epoch.addParameter('backgroundMeans',obj.backgroundMeans);
            
            % Save out the cone/rod contrasts.
            epoch.addParameter('lContrast', obj.coneContrasts(1));
            epoch.addParameter('mContrast', obj.coneContrasts(2));
            epoch.addParameter('sContrast', obj.coneContrasts(3));
            epoch.addParameter('rodContrast', obj.coneContrasts(4));
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
        
    end
end


