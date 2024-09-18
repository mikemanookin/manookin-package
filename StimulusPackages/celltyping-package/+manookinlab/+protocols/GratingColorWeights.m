classdef GratingColorWeights < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Grating leading duration (ms)
        moveTime = 5000                 % Grating duration (ms)
        tailTime = 250                  % Grating trailing duration (ms)
        waitTime = 0                    % Grating wait time before motion (ms)
        contrast = 1.0                  % Grating contrast (0-1)
        orientations = 0                % Grating orientation (deg)
        barWidths = 400                 % Grating half-cycle width (microns)
        temporalFrequencies = 2         % Range of temporal frequencies to test.
        spatialPhase = 0.0              % Spatial phase of grating (deg)
        randomOrder = true              % Random orientation order?
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        apertureRadius = 0              % Aperture radius in microns.
        numberOfSearchValues = 100      % Number of search values to test.
        chromaticClass = 'S-iso-search' % Chromatic class
        apertureClass = 'spot'          % Spot or annulus?       
        spatialClass = 'sinewave'       % Spatial type (sinewave or squarewave)
        temporalClass = 'drifting'      % Temporal type (drifting or reversing)      
        onlineAnalysis = 'none'         % Type of online analysis
        numberOfAverages = uint16(100)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'S-iso-search', 'LM-iso-search'})
        apertureClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'drifting', 'reversing'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        orientationsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        barWidthsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        temporalFrequenciesType = symphonyui.core.PropertyType('denserealdouble','matrix')
        spatialFrequency
        orientation
        phaseShift
        barWidth
        barWidthPix
        apertureRadiusPix
        sequence
        sizeSequence
        freqSequence
        temporalFrequency
        gratingLength
        rgbWeightSequence
        rgbWeights
        spatialPhaseRad
        rawImage
    end
    
    properties (Dependent) 
        stimTime
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if ~obj.isMeaRig
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                if ~strcmp(obj.onlineAnalysis, 'none')
                    obj.showFigure('manookinlab.figures.GratingDSFigure', ...
                        obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                        'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                        'orientations', obj.orientations, ...
                        'temporalFrequency', obj.temporalFrequency);
                end
            end
            
            % Calculate the spatial phase in radians.
            obj.spatialPhaseRad = obj.spatialPhase / 180 * pi;
            
            obj.gratingLength = ceil(sqrt(obj.canvasSize(1)^2 + obj.canvasSize(2)^2));
            
            % Convert from microns to pixels
            obj.apertureRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.apertureRadius);
            obj.organizeParameters();
        end
        
        function organizeParameters(obj)
            
            numSearchesPerAxis = round(sqrt(double(obj.numberOfSearchValues)));
            
            % 
            if strcmp(obj.chromaticClass, 'S-iso-search')
                    w = obj.quantalCatch(:,1:3)' \ [0;0;1];
                    w = w / max(abs(w));
                    redWeights = obj.findBestSearchWeights(w(1), numSearchesPerAxis);
                    greenWeights = obj.findBestSearchWeights(w(2), numSearchesPerAxis);
                    blueWeights = ones(1,numSearchesPerAxis);
            elseif strcmp(obj.chromaticClass, 'LM-iso-search') 
                    w = obj.quantalCatch(:,1:3)' \ [1;1;0];
                    w = w / max(abs(w));
                    redWeights = obj.findBestSearchWeights(w(1), numSearchesPerAxis);
                    greenWeights = w(2)*ones(1,numSearchesPerAxis);
                    blueWeights = w(3) + linspace(-numSearchesPerAxis/2,numSearchesPerAxis/2,numSearchesPerAxis)*0.05;
            end
            
            redWeights = redWeights(:) * ones(1,numSearchesPerAxis);
            greenWeights = greenWeights(:) * ones(1,numSearchesPerAxis);
            blueWeights = blueWeights(:) * ones(1,numSearchesPerAxis);
            
            redWeights = redWeights(:) * ones(1,length(obj.orientations)*length(obj.barWidths)*length(obj.temporalFrequencies));
            greenWeights = greenWeights(:) * ones(1,length(obj.orientations)*length(obj.barWidths)*length(obj.temporalFrequencies));
            blueWeights = blueWeights(:) * ones(1,length(obj.orientations)*length(obj.barWidths)*length(obj.temporalFrequencies));
            redWeights = redWeights(:)';
            greenWeights = greenWeights(:)';
            blueWeights = blueWeights(:)';

            % Generate the list of possible combinations.
            tmp_orient = obj.orientations(:) * ones(1,obj.numberOfSearchValues*length(obj.barWidths)*length(obj.temporalFrequencies));
            tmp_width = obj.barWidths(:) * ones(1,obj.numberOfSearchValues*length(obj.orientations)*length(obj.temporalFrequencies));
            tmp_freq = obj.temporalFrequencies(:) * ones(1,obj.numberOfSearchValues*length(obj.orientations)*length(obj.barWidths));
            tmp_orient = tmp_orient(:)';
            tmp_width = tmp_width(:)';
            tmp_freq = tmp_freq(:)';

            % Calculate the number of repetitions of each annulus type.
            numReps = ceil(double(obj.numberOfAverages) / length(tmp_freq));
            
            % Set the sequence.
            if obj.randomOrder
                obj.sequence = zeros(length(tmp_orient), numReps);
                obj.sizeSequence = zeros(length(tmp_orient), numReps);
                obj.freqSequence = zeros(length(tmp_orient), numReps);
                r_seq = zeros(length(tmp_orient), numReps);
                g_seq = zeros(length(tmp_orient), numReps);
                b_seq = zeros(length(tmp_orient), numReps);
                for k = 1 : numReps
                    epoch_order = randperm(length(tmp_orient));
                    obj.sequence(:,k) = tmp_orient(epoch_order);
                    obj.sizeSequence(:,k) = tmp_width(epoch_order);
                    obj.freqSequence(:,k) = tmp_freq(epoch_order);
                    r_seq(:,k) = redWeights(epoch_order);
                    g_seq(:,k) = greenWeights(epoch_order);
                    b_seq(:,k) = blueWeights(epoch_order);
                end
            else
                obj.sequence = tmp_orient(:) * ones(1, numReps);
                obj.sizeSequence = tmp_width(:) * ones(1, numReps);
                obj.freqSequence = tmp_freq(:) * ones(1, numReps);
                r_seq = redWeights(:) * ones(1, numReps);
                g_seq = greenWeights(:) * ones(1, numReps);
                b_seq = blueWeights(:) * ones(1, numReps);
            end
            obj.sequence = obj.sequence(:)';
            obj.sizeSequence = obj.sizeSequence(:)';
            obj.freqSequence = obj.freqSequence(:)';
            r_seq = r_seq(:)';
            g_seq = g_seq(:)';
            b_seq = b_seq(:)';
            obj.sequence = obj.sequence(1 : obj.numberOfAverages);
            obj.sizeSequence = obj.sizeSequence(1 : obj.numberOfAverages);
            obj.freqSequence = obj.freqSequence(1 : obj.numberOfAverages);
            obj.rgbWeightSequence = zeros(obj.numberOfAverages,3);
            obj.rgbWeightSequence(:,1) = r_seq(1 : obj.numberOfAverages);
            obj.rgbWeightSequence(:,2) = g_seq(1 : obj.numberOfAverages);
            obj.rgbWeightSequence(:,3) = b_seq(1 : obj.numberOfAverages);
        end
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Create the grating.
            grate = stage.builtin.stimuli.Image(uint8(0 * obj.rawImage));
            grate.position = obj.canvasSize / 2;
            grate.size = obj.gratingLength*ones(1,2);
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
                    @(state)setDriftingGrating(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
            else
                imgController = stage.builtin.controllers.PropertyController(grate, 'imageMatrix',...
                    @(state)setReversingGrating(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
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
                if ~strcmp(obj.chromaticClass, 'achromatic')
                    for m = 1 : 3
                        g(:,:,m) = obj.rgbWeights(m) * g(:,:,m);
                    end
                end
                g = uint8(255*(obj.backgroundIntensity * g + obj.backgroundIntensity));
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
                        g(:,:,m) = obj.rgbWeights(m) * g(:,:,m);
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
            sz = obj.gratingLength;
            
            x = linspace(-sz/2, sz/2, sz/downsamp);
            x = x / obj.gratingLength * 2 * pi;
            obj.rawImage = x*obj.spatialFrequency;
            
            if ~strcmp(obj.chromaticClass, 'achromatic')
                obj.rawImage = repmat(obj.rawImage, [1 1 3]);
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Remove the Amp responses if it's an MEA rig.
            if obj.isMeaRig
                amps = obj.rig.getDevices('Amp');
                for ii = 1:numel(amps)
                    if epoch.hasResponse(amps{ii})
                        epoch.removeResponse(amps{ii});
                    end
                    if epoch.hasStimulus(amps{ii})
                        epoch.removeStimulus(amps{ii});
                    end
                end
            end
            
            % Set the RGB weights.
            obj.rgbWeights = obj.rgbWeightSequence(obj.numEpochsCompleted+1,:);
            
            % Set the current orientation.
            obj.orientation = obj.sequence(obj.numEpochsCompleted+1);

            % Set the temporal frequency.
            obj.temporalFrequency = obj.freqSequence(obj.numEpochsCompleted+1);
            
            % Get the bar width in pixels
            obj.barWidth = obj.sizeSequence(obj.numEpochsCompleted+1);
            obj.barWidthPix = obj.rig.getDevice('Stage').um2pix(obj.barWidth);
            epoch.addParameter('barWidth', obj.barWidth);
            
            % Get the spatial frequency.
            obj.spatialFrequency = obj.gratingLength/(2*obj.barWidthPix);
            
            % Set up the raw image.
            obj.setRawImage();

            % Add the spatial frequency to the epoch.
            epoch.addParameter('spatialFrequency', obj.spatialFrequency);

            % Add the temporal frequency in Hz.
            epoch.addParameter('temporalFrequency', obj.temporalFrequency);
            
            % Save out the current orientation.
            epoch.addParameter('orientation', obj.orientation);
            
            % Save out the current RGB weights.
            epoch.addParameter('redWeight', obj.rgbWeights(1));
            epoch.addParameter('greenWeight', obj.rgbWeights(2));
            epoch.addParameter('blueWeight', obj.rgbWeights(3));
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.waitTime + obj.moveTime;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
    methods (Static)
        function optimizedWeights = findBestSearchWeights(thisWeight, numSearchesPerAxis)
            if thisWeight == -1
                optimizedWeights = -1 + (0:(numSearchesPerAxis-1))*0.05;
            elseif thisWeight == 1
                optimizedWeights = 1 - (0:(numSearchesPerAxis-1))*0.05;
            else
                optimizedWeights = thisWeight + linspace(-numSearchesPerAxis/2,numSearchesPerAxis/2,numSearchesPerAxis)*0.05;
            end
        end
    end
end 
