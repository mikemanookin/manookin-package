classdef ConeTyperMonitor < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Spot leading duration (ms)
        stimTime = 500                  % Spot duration (ms)
        tailTime = 500                  % Spot trailing duration (ms)
        contrast = 1.0                  % Contrast (-1 to 1)
        temporalClass = 'pulse'         % Type of temporal modulation
        temporalFrequency = 2.0         % Temporal frequency for non-pulse modulation
        stimulusClass = 'all'           % Chromatic axis to probe
        backgroundIntensity = 0.5       % Background light intensity (0-1)      
        onlineAnalysis = 'none'         % Online analysis type.
        numberOfAverages = uint16(72)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'blue-yellow', 'red-green', 'S-LM', 'L-M', 'all'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'pulse', 'sinewave', 'squarewave'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        bgMean
        stimulusNames
        chromaticClass
        rgbContrasts
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                if numel(obj.rig.getDeviceNames('Amp')) < 2
                    obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                    obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                        obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                        'sweepColor',[30 144 255]/255,...
                        'groupBy',{'frameRate'});
                else
                    obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
                    obj.showFigure('edu.washington.riekelab.figures.DualMeanResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
                end
            end
            
            switch obj.stimulusClass
                case 'blue-yellow'
                    obj.stimulusNames = {'ON','OFF','blue','yellow'};
                case 'S-LM'
                    obj.stimulusNames = {'ON','OFF','S-iso','LM-iso'};
%                 case 'red-green'
%                     obj.stimulusNames = {'ON','OFF','R-G','G-R'};
%                 case 'L-M'
%                     obj.stimulusNames = {'ON','OFF','R-G','G-R','L','M'};
                case 'all'
                    obj.stimulusNames = {'ON','OFF','blue','yellow','S-iso','LM-iso'}; %{'ON','OFF','B-Y','Y-B','S','LM','R-G','G-R','L','M'};
            end
            obj.bgMean = obj.backgroundIntensity*ones(1,3);
            
            if ~strcmp(obj.temporalClass, 'pulse')
                obj.stimulusNames(ismember(obj.stimulusNames,'OFF')) = [];
            end
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.bgMean);
            
            spot = stage.builtin.stimuli.Rectangle();
            spot.size = obj.canvasSize;
            spot.orientation = 0;
            spot.position = obj.canvasSize/2;
            spot.color = obj.rgbContrasts .* obj.bgMean + obj.bgMean;
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            if strcmp(obj.temporalClass, 'sinewave')
                imgController = stage.builtin.controllers.PropertyController(spot, 'color',...
                    @(state)setStimulusSine(obj, state.time - obj.preTime*1e-3));
                p.addController(imgController);
            elseif strcmp(obj.temporalClass, 'squarewave')
                imgController = stage.builtin.controllers.PropertyController(spot, 'color',...
                    @(state)setStimulusSquare(obj, state.time - obj.preTime*1e-3));
                p.addController(imgController);
            end
            
            function c = setStimulusSine(obj, time)
                if time >= 0
                    c = obj.bgMean .* (obj.contrast * sin(obj.temporalFrequency * time * 2 * pi) * obj.rgbContrasts) + obj.bgMean;
                else
                    c = obj.bgMean;
                end
            end
            
            function c = setStimulusSquare(obj, time)
                if time >= 0
                    c = obj.bgMean .* (obj.contrast * sign(sin(obj.temporalFrequency * time * 2 * pi)) * obj.rgbContrasts) + obj.bgMean;
                else
                    c = obj.bgMean;
                end
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current stimulus name
            obj.chromaticClass = obj.stimulusNames{mod(obj.numEpochsPrepared - 1,length(obj.stimulusNames))+1};
            epoch.addParameter('chromaticClass',obj.chromaticClass);
            
            switch obj.chromaticClass
                case 'ON'
                    obj.rgbContrasts = ones(1,3);
                case 'OFF'
                    obj.rgbContrasts = -1*ones(1,3);
                case 'S-iso'
                    obj.rgbContrasts = obj.getDeltaRGB(0.5*ones(1,3), [0;0;1]); %[0.779174761176273, -0.418329218657993, 1];
                case 'LM-iso'
                    obj.rgbContrasts = obj.getDeltaRGB(0.5*ones(1,3), [1;1;0]); %[-0.823447657789278, 1, -0.444877821696775];
                case 'blue'
                    obj.rgbContrasts = [0, 0, 1];
                case 'yellow'
                    obj.rgbContrasts = [1, 1, 0];
            end
            obj.rgbContrasts = obj.rgbContrasts(:)';
        end
        
        function deltaRGB = getDeltaRGB(obj, gunMeans, isoM)
            deltaRGB = 2*(obj.quantalCatch(:,1:3).*(ones(3,1)*gunMeans(:)')')' \ isoM;
            deltaRGB = deltaRGB / max(abs(deltaRGB));
        end

        function cWeber = getConeContrasts(obj, gunMeans, deltaRGB)
            meanFlux = (gunMeans(:)*ones(1,3)) .* obj.quantalCatch(:,1:3);

            iDelta = sum((deltaRGB(:)*ones(1,3)) .* meanFlux);
            % Calculate the max contrast of each cone type. (Weber contrast)
            cWeber = iDelta ./ sum(meanFlux,1);
        end
        
        function a = get.amp2(obj)
            amps = obj.rig.getDeviceNames('Amp');
            if numel(amps) < 2
                a = '(None)';
            else
                i = find(~ismember(amps, obj.amp), 1);
                a = amps{i};
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