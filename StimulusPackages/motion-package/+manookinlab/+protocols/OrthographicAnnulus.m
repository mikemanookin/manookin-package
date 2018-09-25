classdef OrthographicAnnulus < manookinlab.protocols.ManookinLabStageProtocol
    properties
        preTime = 250
        waitTime = 750
        stimTime = 1500
        tailTime = 250
        sequence = 'expanding-light'
        contrast = 0.5
        speed = 3000 % pix/sec
        widthPix = 25
        minRadius = 50 
        maxRadius = 150
        backgroundIntensity = 0.5 % (0-1)
        centerOffset = [0, 0] % [x,y] (pix)
        spatialClass = 'annulus'
        onlineAnalysis = 'none'
        numberOfAverages = uint16(12) % number of epochs to queue
        amp
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthreshold', 'analog'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'annulus','spot','grating'})
        sequenceType = symphonyui.core.PropertyType('char', 'row', {'expanding-light', 'contracting-light', 'expanding-dark', 'contracting-dark'})
        intensity
        direction
        maskRadius
        moveRadius
        stopRadius
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
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',[0 0 0],...
                'groupBy',{'direction'});
            
            % Organize the sequence parameters before you start the run.
            obj.organizeParameters();
        end
        
        function organizeParameters(obj)

            switch obj.sequence
                case 'expanding-light'
                    obj.intensity = 1;
                    obj.direction = 1;
                case 'contracting-light'
                    obj.intensity = 1;
                    obj.direction = -1; 
                case 'expanding-dark'
                    obj.intensity = -1;
                    obj.direction = 1;
                case 'contracting-dark'
                    obj.intensity = -1;
                    obj.direction = -1;
            end
            
            % Adjust the intensity based on the contrast.
            if obj.backgroundIntensity == 0
                obj.intensity = obj.contrast * obj.intensity;
            else
                obj.intensity = obj.backgroundIntensity*(obj.contrast * obj.intensity) + obj.backgroundIntensity;
            end 
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            spot = stage.builtin.stimuli.Ellipse();
            spot.color = obj.intensity;
            spot.radiusX = obj.moveRadius;
            spot.radiusY = obj.moveRadius;
            spot.position = canvasSize/2 + obj.centerOffset;
            p.addStimulus(spot);
            
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            % Create a radius controller.
            outerRadiusX = stage.builtin.controllers.PropertyController(spot, 'radiusX',...
                @(state)getOuterRadius(obj, state.time - (obj.preTime+obj.waitTime)/1e3));
            p.addController(outerRadiusX);
            
            outerRadiusY = stage.builtin.controllers.PropertyController(spot, 'radiusY',...
                @(state)getOuterRadius(obj, state.time - (obj.preTime+obj.waitTime)/1e3));
            p.addController(outerRadiusY);
            
            function r = getOuterRadius(obj, time)
                r = obj.direction * obj.speed * time + obj.moveRadius;
                r = max(r, obj.minRadius);
                r = min(r, obj.maxRadius);
            end
            
            % Create the mask spot.
            mask = stage.builtin.stimuli.Ellipse();
            mask.color = obj.backgroundIntensity;
            mask.radiusX = obj.moveRadius - obj.widthPix;
            mask.radiusY = obj.moveRadius - obj.widthPix;
            mask.position = canvasSize/2 + obj.centerOffset;
            p.addStimulus(mask);
            
            % Create a radius controller.
            innerRadiusX = stage.builtin.controllers.PropertyController(mask, 'radiusX',...
                @(state)getInnerRadius(obj, state.time - (obj.preTime+obj.waitTime)/1e3));
            p.addController(innerRadiusX);
            
            innerRadiusY = stage.builtin.controllers.PropertyController(mask, 'radiusY',...
                @(state)getInnerRadius(obj, state.time - (obj.preTime+obj.waitTime)/1e3));
            p.addController(innerRadiusY);
            
            function r = getInnerRadius(obj, time)
                r = obj.direction * obj.speed * time + obj.moveRadius - obj.widthPix;
                r = max(r, obj.minRadius - obj.widthPix);
                r = min(r, obj.maxRadius - obj.widthPix);
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            if obj.direction == 1
                obj.moveRadius = obj.minRadius;
                epoch.addParameter('direction', 'outward');
            else
                obj.moveRadius = obj.maxRadius;
                epoch.addParameter('direction', 'inward');
            end
            
            epoch.addParameter('intensity', obj.intensity);
        end
        
        % Same presentation each epoch in a run. Replay.
        function controllerDidStartHardware(obj)
            controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            if (obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < obj.numberOfAverages)
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