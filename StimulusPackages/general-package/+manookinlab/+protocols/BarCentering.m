classdef BarCentering < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Spot leading duration (ms)
        stimTime = 2000                 % Spot duration (ms)
        tailTime = 1000                 % Spot trailing duration (ms)
        intensity = 1.0                 % Bar intensity (0-1)
        temporalFrequency = 2.0         % Modulation frequency (Hz)
        barSize = [50 1000]              % Bar size [width, height] (um)
        searchAxis = 'xaxis'            % Search axis
        temporalClass = 'squarewave'    % Squarewave or pulse?
        positions = -300:50:300         % Bar center position (um)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        chromaticClass = 'achromatic'   % Chromatic class
        onlineAnalysis = 'extracellular'         % Online analysis type.
        numberOfAverages = uint16(13)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        searchAxisType = symphonyui.core.PropertyType('char', 'row', {'xaxis', 'yaxis'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'squarewave', 'pulse'})
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic', 'red', 'green', 'blue', 'yellow', 'L-iso', 'M-iso', 'S-iso', 'LM-iso'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        position
        orientation
        sequence
        F1
        F2
        xaxis
        bkg
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
            
            obj.showFigure('manookinlab.figures.ResponseFigure', obj.rig.getDevices('Amp'), ...
                'numberOfAverages', obj.numberOfAverages);
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.analysisFigure = obj.showFigure('symphonyui.builtin.figures.CustomFigure', @obj.CTRanalysis);
                f = obj.analysisFigure.getFigureHandle();
                set(f, 'Name', 'bar centering');
                obj.analysisFigure.userData.axesHandle = axes('Parent', f);
            end
            
            % Create the matrix of bar positions.
            numReps = ceil(double(obj.numberOfAverages) / length(obj.positions));
            
            % Get the array of radii.
            pos = obj.positions(:) * ones(1, numReps);
            pos = pos(:);
            % Convert from um to pix
            pos = obj.rig.getDevice('Stage').um2pix(pos);
            obj.xaxis = pos';
            obj.F1 = zeros(1,length(pos));
            obj.F2 = zeros(1,length(pos));
            
            if strcmp(obj.searchAxis, 'xaxis')
                obj.orientation = 0;
                obj.sequence = [pos+obj.centerOffset(1) obj.centerOffset(2)*ones(length(pos),1)];
            else
                obj.orientation = 90;
                obj.sequence = [obj.centerOffset(1)*ones(length(pos),1) pos+obj.centerOffset(2)];
            end
            
            if strcmp(obj.stageClass, 'LightCrafter')
                obj.chromaticClass = 'achromatic';
            end
            
            if (obj.backgroundIntensity == 0 || strcmp(obj.chromaticClass, 'achromatic'))
                obj.bkg = 0.5;
            else
                obj.bkg = obj.backgroundIntensity;
            end
            
            obj.setColorWeights();
        end
        
        function CTRanalysis(obj, ~, epoch)
            response = epoch.getResponse(obj.rig.getDevice(obj.amp));
            responseTrace = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            
            % Analyze response by type.
            responseTrace = obj.getResponseByType(responseTrace, obj.onlineAnalysis);
            
            %--------------------------------------------------------------
            if strcmp(obj.temporalClass, 'squarewave')
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

                % Get the F1 and F2 responses.
                f = abs(ft(2:3))/length(ft)*2;

                obj.F1(obj.numEpochsCompleted) = f(1);
                obj.F2(obj.numEpochsCompleted) = f(2);
            else % Pulse analysis
                if ~strcmp(obj.onlineAnalysis, 'extracellular') && ~strcmp(obj.onlineAnalysis, 'spikes_CClamp') 
                    % Subtract the baseline.
                    responseTrace = responseTrace - mean(responseTrace(1 : round(obj.preTime/1000*sampleRate)));
                end
                responseTrace = responseTrace(obj.preTime/1000*sampleRate+1 : end);
                obj.F1(obj.numEpochsCompleted) = mean(responseTrace(1 : floor(obj.stimTime/1000*sampleRate)));
                obj.F2(obj.numEpochsCompleted) = mean(responseTrace(floor(obj.stimTime/1000*sampleRate)+1 : end));
            end
            %--------------------------------------------------------------
            
            axesHandle = obj.analysisFigure.userData.axesHandle;
            cla(axesHandle);
            hold(axesHandle, 'on');
            plot(obj.xaxis, obj.F1, 'ko-', 'Parent', axesHandle);
            plot(obj.xaxis, obj.F2, 'ro-', 'Parent', axesHandle);
            hold(axesHandle, 'off');
            set(axesHandle, 'TickDir', 'out');
            ylabel(axesHandle, 'F1/F2 amp');
            title(['Epoch ', num2str(obj.numEpochsCompleted), ' of ', num2str(obj.numberOfAverages)], 'Parent', axesHandle);
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.rig.getDevice('Stage').um2pix(obj.barSize); % um -> pix
            rect.orientation = obj.orientation;
            rect.position = obj.canvasSize/2 + obj.position;
            
            if strcmp(obj.stageClass, 'Video')
                rect.color = obj.intensity*obj.colorWeights*obj.bkg + obj.bkg;
            else
                rect.color = obj.intensity*obj.bkg + obj.bkg;
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect);       
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            % Control the bar intensity.
            if strcmp(obj.temporalClass, 'squarewave')
                colorController = stage.builtin.controllers.PropertyController(rect, 'color', ...
                    @(state)getSpotColorVideoSqwv(obj, state.time - obj.preTime * 1e-3));
                p.addController(colorController);
            end
            
            function c = getSpotColorVideoSqwv(obj, time)       
                if strcmp(obj.stageClass, 'Video')
                    c = obj.intensity * sign(sin(obj.temporalFrequency*time*2*pi)) * obj.colorWeights * obj.bkg + obj.bkg;
                else
                    c = obj.intensity * sign(sin(obj.temporalFrequency*time*2*pi)) * obj.bkg + obj.bkg;
                end
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.position = obj.sequence(obj.numEpochsCompleted+1, :);
            if strcmp(obj.searchAxis, 'xaxis')
                epoch.addParameter('position', obj.position(1));
            else
                epoch.addParameter('position', obj.position(2));
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