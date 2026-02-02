classdef MovingBar < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Bar leading duration (ms)
        stimTime = 2500                 % Bar duration (ms)
        tailTime = 500                  % Bar trailing duration (ms)
        orientations = 0:30:330         % Bar angle (deg)
        speed = 1000                    % Bar speed (pix/sec)
        intensity = 1.0                 % Max light intensity (0-1)
        barSize = [600, 600]            % Bar size (x,y) in microns
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        innerMaskRadius = 0             % Inner mask radius in microns.
        outerMaskRadius = 570           % Outer mask radius in microns.
        randomOrder = true              % Random orientation order?
        onlineAnalysis = 'extracellular'         % Online analysis type.
        numberOfAverages = uint16(36)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        orientationsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        sequence
        orientation
        orientationRads
        barSizePix
        innerMaskRadiusPix
        outerMaskRadiusPix
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.barSizePix = obj.rig.getDevice('Stage').um2pix(obj.barSize);
            obj.innerMaskRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.innerMaskRadius);
            obj.outerMaskRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.outerMaskRadius);
            
            if length(obj.orientations) > 1
                colors = pmkmp(length(obj.orientations),'CubicYF');
            else
                colors = zeros(1,3);
            end
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'orientation'});
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.DirectionFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                    'orientations', unique(obj.orientations));
            end
            
            % Get the frame rate. Need to check if it's a LCR rig.
            if ~isempty(strfind(obj.rig.getDevice('Stage').name, 'LightCrafter'))
                obj.frameRate = obj.rig.getDevice('Stage').getPatternRate();
            else
                obj.frameRate = obj.rig.getDevice('Stage').getMonitorRefreshRate();
            end
            
            % Get the canvas size.
            obj.canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            
            % Check the outer mask radius.
            if obj.outerMaskRadiusPix > min(obj.canvasSize/2)
                obj.outerMaskRadiusPix = min(obj.canvasSize/2);
            end
            
            obj.organizeParameters();
        end
        
        function organizeParameters(obj)
            % Calculate the number of repetitions of each annulus type.
            numReps = ceil(double(obj.numberOfAverages) / length(obj.orientations));
            
            % Set the sequence.
            if obj.randomOrder
                obj.sequence = zeros(length(obj.orientations), numReps);
                for k = 1 : numReps
                    obj.sequence(:,k) = obj.orientations(randperm(length(obj.orientations)));
                end
            else
                obj.sequence = obj.orientations(:) * ones(1, numReps);
            end
            obj.sequence = obj.sequence(:)';
            obj.sequence = obj.sequence(1 : obj.numberOfAverages);
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.barSizePix;
            rect.position = obj.canvasSize/2;
            rect.orientation = obj.orientation;
            rect.color = obj.intensity;
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect);
            
            barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(barVisible);
            
            % Bar position controller
            barPosition = stage.builtin.controllers.PropertyController(rect, 'position', ...
                @(state)motionTable(obj, state.time - obj.preTime*1e-3));
            p.addController(barPosition);
            
            function p = motionTable(obj, time)
                % Calculate the increment with time.  
                inc = time * obj.speed - obj.outerMaskRadiusPix - obj.barSizePix(1)/2 ;
                
                p = [cos(obj.orientationRads) sin(obj.orientationRads)] .* (inc*ones(1,2)) + obj.canvasSize/2;
            end
            
            % Create the inner mask.
            if (obj.innerMaskRadiusPix > 0)
                p.addStimulus(obj.makeInnerMask());
            end
            
            % Create the outer mask.
            if (obj.outerMaskRadiusPix > 0)
                p.addStimulus(obj.makeOuterMask());
            end
        end
        
        function mask = makeOuterMask(obj)
            mask = stage.builtin.stimuli.Rectangle();
            mask.color = obj.backgroundIntensity;
            mask.position = obj.canvasSize/2;
            mask.orientation = 0;
            mask.size = 2 * max(obj.canvasSize) * ones(1,2);
            sc = obj.outerMaskRadiusPix*2 / (2*max(obj.canvasSize));
            m = stage.core.Mask.createCircularAperture(sc);
            mask.setMask(m);
        end
        
        function mask = makeInnerMask(obj)
            mask = stage.builtin.stimuli.Ellipse();
            mask.radiusX = obj.innerMaskRadiusPix;
            mask.radiusY = obj.innerMaskRadiusPix;
            mask.color = obj.backgroundIntensity;
            mask.position = obj.canvasSize/2;
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current bar orientation.
            obj.orientation = obj.sequence(obj.numEpochsCompleted+1);
            obj.orientationRads = obj.orientation / 180 * pi;
            
            epoch.addParameter('orientation', obj.orientation);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
