classdef LinearSumDxBars < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Stimulus leading duration (ms)
        stimTime = 100                  % Stimulus duration (ms)
        tailTime = 900                  % Stimulus trailing duration (ms)
        pulseFrames = 2                 % Stimulus pulse duration (frames)
        barSize = [50 200]              % Bar size (pixels)
        dxVals = [50, 70, 90, 110, 130]% Spatial offset of flash centers (pix)
        contrast1 = 0.5                 % Rectangle #1 contrast (-1:1)
        contrast2 = 0.5                 % Rectangle #2 contrast (0-1)
        orientation = 0                 % Bar orientation (degrees)
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
        dx
        dxSeq
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
%             if ~strcmp(obj.onlineAnalysis, 'none')
%                 obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
%                     obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
%                     'sweepColor',colors,...
%                     'groupBy',{'stimulusName'});
%             end
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.LinearSumFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',colors, 'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                    'sortName', 'dx', 'sortValues', unique(obj.dxVals));
            end
            
            % dxSeq
            numReps = ceil(double(obj.numberOfAverages)/(3*length(obj.dxVals)));
            obj.dxSeq = ones(3,1) * obj.dxVals(:)';
            obj.dxSeq = obj.dxSeq(:) * ones(1, numReps);
            obj.dxSeq = obj.dxSeq(:)';
            obj.dxSeq = obj.dxSeq( 1 : obj.numberOfAverages );
            
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
            
            % Calculate the pulse time in seconds
            obj.pulseTime = obj.pulseFrames / obj.frameRate;
            
            % Calculate the flash intensities.
            obj.intensity1 = obj.contrast1*obj.backgroundIntensity+obj.backgroundIntensity;
            obj.intensity2 = obj.contrast2*obj.backgroundIntensity+obj.backgroundIntensity;
            
            % Check the intensities.
            obj.intensity1 = max(obj.intensity1, 0);
            obj.intensity1 = min(obj.intensity1, 1);
            obj.intensity2 = max(obj.intensity2, 0);
            obj.intensity2 = min(obj.intensity2, 1);
            
            % Convert back to contrast.
            obj.contrast1 = (obj.intensity1 - obj.backgroundIntensity) / obj.backgroundIntensity;
            obj.contrast2 = (obj.intensity2 - obj.backgroundIntensity) / obj.backgroundIntensity;
            
            % Get the center offset based on the orientation.
            orientationRads = obj.orientation / 180 * pi;
            obj.centerPosition = [cos(orientationRads) sin(orientationRads)];
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            
            
            rect1 = stage.builtin.stimuli.Rectangle();
            rect1.size = obj.barSize;
            rect1.position = obj.canvasSize/2 + obj.centerOffset + obj.dx/2*obj.centerPosition; %[obj.dx/2 0];
            rect1.orientation = obj.orientation;
            if strcmpi(obj.stimulusName, 'bar2')
                rect1.color = obj.backgroundIntensity;
            else
                rect1.color = obj.intensity1;
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect1);
            
            bar1Visible = stage.builtin.controllers.PropertyController(rect1, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.pulseTime) * 1e-3);
            p.addController(bar1Visible);
            
            % Create the second rectangle.
            rect2 = stage.builtin.stimuli.Rectangle();
            rect2.size = obj.barSize;
            rect2.position = obj.canvasSize/2 + obj.centerOffset - obj.dx/2*obj.centerPosition; %[obj.dx/2 0];
            rect2.orientation = obj.orientation;
            if strcmpi(obj.stimulusName, 'bar1')
                rect2.color = obj.backgroundIntensity;
            else
                rect2.color = obj.intensity2;
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect2);
            
            bar2Visible = stage.builtin.controllers.PropertyController(rect2, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.pulseTime) * 1e-3);
            p.addController(bar2Visible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the frame delay.
            obj.stimulusName = obj.sequenceNames{obj.sequence( obj.numEpochsCompleted+1 )};
            obj.dx = obj.dxSeq( obj.numEpochsCompleted+1 );

            % Save the frame delay
            epoch.addParameter('stimulusName', obj.stimulusName);
            epoch.addParameter('pulseTime', obj.pulseTime);
            epoch.addParameter('dx', obj.dx);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end