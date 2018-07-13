classdef SpaceTimeOffsetFlash < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 500                  % Stimulus duration (ms)
        tailTime = 500                  % Stimulus trailing duration (ms)
        pulseFrames = 1                 % Stimulus pulse duration (frames)
        delayFrames = [0:6 8:2:12]      % Delay frames for second square.
        barSize = [50 100]              % Bar size (pixels)
        dx = 90                         % Spatial offset of flash centers (pix)
        contrast1 = 0.5                 % Rectangle #1 contrast (-1:1)
        contrast2 = 1.0                 % Rectangle #2 contrast (0-1)
        orientation = 0                 % Bar orientation (degrees)
        direction = 'inward'            % 'centered','inward', or 'outward'
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Online analysis type.
        randomOrder = true              % Random dt sequence?
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        numberOfAverages = uint16(120)  % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        directionType = symphonyui.core.PropertyType('char','row', {'none', 'inward', 'outward'})
        sequence
        dt
        dtSec
        pulseTime
        intensity1
        intensity2
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if length(obj.delayFrames) > 1
                colors = pmkmp(length(obj.delayFrames),'CubicYF');
            else
                colors = [0 0 0];
            end
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'dt'});
            
            % Get the correlation sequence.
            numReps = ceil(double(obj.numberOfAverages)/length(obj.delayFrames));
            if obj.randomOrder
                obj.sequence = zeros(1, numReps*length(obj.delayFrames));
                for k = 1 : numReps
                    s = randperm(length(obj.delayFrames));
                    obj.sequence((k-1)*length(obj.delayFrames)+1 : k*length(obj.delayFrames)) = s;
                end
            else
                obj.sequence = (1 : length(obj.delayFrames))' * ones(1, numReps);
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
        end
        
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Calculate the orientation in radians.
            orientationRads = obj.orientation/180*pi;
            
            rect1 = stage.builtin.stimuli.Rectangle();
            rect1.size = obj.barSize;
            rect1.orientation = obj.orientation;
            
            % Position. {'none', 'inward', 'outward'}
            switch obj.direction
                case 'inward'
                    rect1.position = obj.canvasSize/2 + obj.centerOffset + [cos(orientationRads) sin(orientationRads)] .* (obj.dx*ones(1,2));
                    rect1.color = obj.intensity2;
                case 'outward'
                    rect1.position = obj.canvasSize/2 + obj.centerOffset;
                    rect1.color = obj.intensity1;
                otherwise
                    rect1.position = obj.canvasSize/2 + obj.centerOffset + [cos(orientationRads) sin(orientationRads)] .* (obj.dx/2*ones(1,2));
                    rect1.color = obj.intensity2;
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect1);
            
            bar1Visible = stage.builtin.controllers.PropertyController(rect1, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.pulseTime) * 1e-3);
            p.addController(bar1Visible);
            
            % Create the second rectangle.
            rect2 = stage.builtin.stimuli.Rectangle();
            rect2.size = obj.barSize;
            rect2.orientation = obj.orientation;
            
            % Position. {'none', 'inward', 'outward'}
            switch obj.direction
                case 'inward'
                    rect2.position = obj.canvasSize/2 + obj.centerOffset;
                    rect2.color = obj.intensity1;
                case 'outward'
                    rect2.position = obj.canvasSize/2 + obj.centerOffset + [cos(orientationRads) sin(orientationRads)] .* (obj.dx*ones(1,2));
                    rect2.color = obj.intensity2;
                otherwise
                    rect2.position = obj.canvasSize/2 + obj.centerOffset - [cos(orientationRads) sin(orientationRads)] .* (obj.dx/2*ones(1,2));
                    rect2.color = obj.intensity1;
            end
            
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect2);
            
            bar2Visible = stage.builtin.controllers.PropertyController(rect2, 'visible', ...
                @(state)state.time >= (obj.preTime) * 1e-3 + obj.dtSec && state.time < (obj.preTime + obj.pulseTime) * 1e-3 + obj.dtSec);
            p.addController(bar2Visible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the frame delay.
            obj.dt = obj.delayFrames(obj.sequence( obj.numEpochsCompleted+1 ));
            obj.dtSec = obj.dt/obj.frameRate;

            % Save the frame delay
            epoch.addParameter('dt', obj.dt);
            epoch.addParameter('dtMsec', obj.dt/obj.frameRate*1e3);
            epoch.addParameter('pulseTime', obj.pulseTime);
        end
        
        % Same presentation each epoch in a run. Replay.
        function controllerDidStartHardware(obj)
            controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            if (obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < obj.numberOfAverages) && length(obj.delayFrames) == 1
                obj.rig.getDevice('Stage').replay
            else
                obj.rig.getDevice('Stage').play(obj.createPresentation());
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