classdef LMIsoSearch < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 500                   % Spot leading duration (ms)
        stimTime = 3000                 % Spot duration (ms)
        tailTime = 500                  % Spot trailing duration (ms)
        chromaticClass = 'L-iso'        % Cone-iso type (L or M)
        temporalClass = 'squarewave'    % Temporal waveform
        temporalFrequency = 2.0         % Modulation frequency (Hz)
        radius = 150                    % Spot radius (pix)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        onlineAnalysis = 'extracellular'         % Online analysis type.
        numberOfAverages = uint16(40)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave', 'pulse'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'L-iso','M-iso'})
        ledValues
        ledContrasts
        searchValues
        R
        repsPerX
        currentSearchValue
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
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.analysisFigure = obj.showFigure('symphonyui.builtin.figures.CustomFigure', @obj.MTFanalysis);
                f = obj.analysisFigure.getFigureHandle();
                set(f, 'Name', 'iso search');
                obj.analysisFigure.userData.axesHandle = axes('Parent', f);
            end
            
            % Set the LED weights.
            obj.setColorWeights();
            obj.ledContrasts = obj.colorWeights;
            obj.ledValues = obj.backgroundIntensity*obj.colorWeights + obj.backgroundIntensity;
            
            % Set the bit-wise search values.
            obj.searchValues = [255 (248:-8:104) (100:-2:92) (84:-8:52) (50:-2:42) (34:-8:0)]/255;
            obj.R = zeros(length(unique(obj.searchValues)),2);
            obj.repsPerX = zeros(size(unique(obj.searchValues)));
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
            
            % Find the x-index
            index = find(obj.searchValues == obj.currentSearchValue, 1);
            obj.R(index,:) = (obj.R(index) * obj.repsPerX(index) + ...
                [mean(cycleData(1:floor(binsPerCycle))) mean(cycleData(ceil(binsPerCycle)+1:end))])/(obj.repsPerX(index) + 1);
            obj.repsPerX(index) = obj.repsPerX(index) + 1;
            
            axesHandle = obj.analysisFigure.userData.axesHandle;
            cla(axesHandle);
            hold(axesHandle, 'on');
            plot(unique((obj.searchValues-obj.backgroundIntensity)/obj.backgroundIntensity),obj.R, 'o-', 'Parent', axesHandle);
            hold(axesHandle, 'off');
            set(axesHandle, 'TickDir', 'out');
            ylabel(axesHandle, 'response');
            title(['theoretical: ', num2str(obj.colorWeights(:)')], 'Parent', axesHandle);
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            spot = stage.builtin.stimuli.Ellipse();
            spot.radiusX = obj.radius;
            spot.radiusY = obj.radius;
            spot.position = obj.canvasSize/2 + obj.centerOffset;
            spot.color = obj.ledValues;
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time > obj.preTime * 1e-3 && state.time <= (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);

            % Modulate the spot contrast.
            if strcmp(obj.temporalClass, 'sinewave')
                colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                    @(state)getSpotColorVideo(obj, state.time - obj.preTime * 1e-3));
                p.addController(colorController);
            elseif strcmp(obj.temporalClass, 'squarewave')
                colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                    @(state)getSpotColorVideoSqwv(obj, state.time - obj.preTime * 1e-3));
                p.addController(colorController);
            end
            
            function c = getSpotColorVideo(obj, time)
                c = obj.ledContrasts * sin(obj.temporalFrequency*time*2*pi) * obj.backgroundIntensity + obj.backgroundIntensity;
            end
            
            function c = getSpotColorVideoSqwv(obj, time)
                c = obj.ledContrasts * sign(sin(obj.temporalFrequency*time*2*pi)) * obj.backgroundIntensity + obj.backgroundIntensity;
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current search value.
            v = obj.searchValues(mod(obj.numEpochsCompleted, length(obj.searchValues)) + 1);
            if strcmp(obj.chromaticClass, 'L-iso')
                obj.ledValues(2) = v;
                obj.ledContrasts(2) = (v - obj.backgroundIntensity)/obj.backgroundIntensity;
            else
                obj.ledValues(1) = v;
                obj.ledContrasts(1) = (v - obj.backgroundIntensity)/obj.backgroundIntensity;
            end
            obj.currentSearchValue = v;
            
            % Add parameters you'll need for analysis.
            epoch.addParameter('ledValues', obj.ledValues);
            epoch.addParameter('ledContrasts',obj.ledContrasts);
            epoch.addParameter('colorWeights', obj.colorWeights);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end