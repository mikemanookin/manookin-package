classdef LinearSummationSpots < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Stimulus leading duration (ms)
        stimTime = 100                  % Stimulus duration (ms)
        tailTime = 900                  % Stimulus trailing duration (ms)
        contrast1 = 0.75                % Rectangle #1 contrast (-1:1)
        contrast2 = 0.75                % Rectangle #2 contrast (-1:1)
        spot1Offset = [0,0]
        spot2Offset = [0,0]
        spot1Radius = 50
        spot2Radius = 50
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Online analysis type.
        randomOrder = true              % Random sequence?
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        numberOfAverages = uint16(120)  % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        sequenceNames = {'bar1','bar2','both bars'}
        stimulusName
        sequence
        pulseTime
        intensity1
        intensity2
        centerPosition
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if length(obj.sequenceNames) > 1
                colors = pmkmp(length(obj.sequenceNames),'CubicYF');
            else
                colors = [0 0 0];
            end
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
%             obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
%                 obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
%                 'sweepColor',colors,...
%                 'groupBy',{'stimulusName'});
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.LinearSumFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',colors,'preTime', obj.preTime, 'stimTime', obj.stimTime);
            end
            
            % Get the correlation sequence.
            numReps = ceil(double(obj.numberOfAverages)/length(obj.sequenceNames));
            if obj.randomOrder
                obj.sequence = zeros(1, numReps*length(obj.sequenceNames));
                for k = 1 : numReps
                    s = randperm(length(obj.sequenceNames));
                    obj.sequence((k-1)*length(obj.sequenceNames)+1 : k*length(obj.sequenceNames)) = s;
                end
            else
                obj.sequence = (1 : length(obj.sequenceNames))' * ones(1, numReps);
                obj.sequence = obj.sequence(:)';
            end
            % Just take the ones you need.
            obj.sequence = obj.sequence( 1 : obj.numberOfAverages );
            
            % Calculate the flash intensities.
            if obj.backgroundIntensity > 0
                obj.intensity1 = obj.contrast1*obj.backgroundIntensity+obj.backgroundIntensity;
                obj.intensity2 = obj.contrast2*obj.backgroundIntensity+obj.backgroundIntensity;
            else
                obj.intensity1 = obj.contrast1;
                obj.intensity2 = obj.contrast2;
            end
            
            % Check the intensities.
            obj.intensity1 = max(obj.intensity1, 0);
            obj.intensity1 = min(obj.intensity1, 1);
            obj.intensity2 = max(obj.intensity2, 0);
            obj.intensity2 = min(obj.intensity2, 1);
            
            % Convert back to contrast.
            if obj.backgroundIntensity > 0
                obj.contrast1 = (obj.intensity1 - obj.backgroundIntensity) / obj.backgroundIntensity;
                obj.contrast2 = (obj.intensity2 - obj.backgroundIntensity) / obj.backgroundIntensity;
            end
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            rect1 = stage.builtin.stimuli.Ellipse();
            rect1.radiusX = obj.spot1Radius;
            rect1.radiusY = obj.spot1Radius;
            rect1.position = obj.canvasSize/2 + obj.spot1Offset;
            if strcmpi(obj.stimulusName, 'bar2')
                rect1.color = obj.backgroundIntensity;
            else
                rect1.color = obj.intensity1;
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect1);
            
            bar1Visible = stage.builtin.controllers.PropertyController(rect1, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(bar1Visible);
            
            % Create the second rectangle.
            rect2 = stage.builtin.stimuli.Ellipse();
            rect2.radiusX = obj.spot2Radius;
            rect2.radiusY = obj.spot2Radius;
            rect2.position = obj.canvasSize/2 + obj.spot2Offset;
            if strcmpi(obj.stimulusName, 'bar1')
                rect2.color = obj.backgroundIntensity;
            else
                rect2.color = obj.intensity2;
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect2);
            
            bar2Visible = stage.builtin.controllers.PropertyController(rect2, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(bar2Visible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the frame delay.
            obj.stimulusName = obj.sequenceNames{obj.sequence( obj.numEpochsCompleted+1 )};

            % Save the frame delay
            epoch.addParameter('stimulusName', obj.stimulusName);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end