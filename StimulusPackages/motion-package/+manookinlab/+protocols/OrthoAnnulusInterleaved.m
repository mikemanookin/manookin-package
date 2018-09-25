classdef OrthoAnnulusInterleaved < manookinlab.protocols.ManookinLabStageProtocol
    properties
        preTime = 250
        waitTime = 1250
        stimTime = 2000
        tailTime = 1000
        contrasts = [-1, 0.25, 0.25:0.25:1]
        speed = 3000 % pix/sec
        widthPix = 50
        minRadius = 50 
        maxRadius = 150
        backgroundIntensity = 0.5 % (0-1)
        spatialClass = 'annulus'
        onlineAnalysis = 'extracellular'
        numberOfAverages = uint16(72) % number of epochs to queue
        amp
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthreshold', 'analog'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'annulus','spot','grating'})
        intensity
        direction
        maskRadius
        moveRadius
        stopRadius
        contrast
        sequence
        directions
        contrastSeq
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            % Get the color sequence for plotting.
            colors = pmkmp(length(unique(obj.contrasts))*2,'CubicYF');
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'contrast','direction'});
            
            % Organize the sequence parameters before you start the run.
            obj.organizeParameters();
        end
        
        function organizeParameters(obj)
            % Get the contrast sequence.
            numReps = ceil(double(obj.numberOfAverages)/(length(obj.contrasts)*2));
            obj.contrastSeq = ones(2,1) * obj.contrasts(:)';
            obj.contrastSeq = obj.contrastSeq(:) * ones(1, numReps);
            obj.contrastSeq = obj.contrastSeq(:)';
            
            % Get the motion directions.
            numReps = ceil(double(obj.numberOfAverages)/2);
            obj.directions = [1; -1] * ones(1, numReps);
            obj.directions = obj.directions(:)';
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            spot = stage.builtin.stimuli.Ellipse();
            spot.color = obj.intensity;
            spot.radiusX = obj.moveRadius;
            spot.radiusY = obj.moveRadius;
            spot.position = canvasSize/2;
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
            
            if strcmp(obj.spatialClass, 'annulus')
                % Create the mask spot.
                mask = stage.builtin.stimuli.Ellipse();
                mask.color = obj.backgroundIntensity;
                mask.radiusX = obj.moveRadius - obj.widthPix;
                mask.radiusY = obj.moveRadius - obj.widthPix;
                mask.position = canvasSize/2;
                p.addStimulus(mask);

                % Create a radius controller.
                innerRadiusX = stage.builtin.controllers.PropertyController(mask, 'radiusX',...
                    @(state)getInnerRadius(obj, state.time - (obj.preTime+obj.waitTime)/1e3));
                p.addController(innerRadiusX);

                innerRadiusY = stage.builtin.controllers.PropertyController(mask, 'radiusY',...
                    @(state)getInnerRadius(obj, state.time - (obj.preTime+obj.waitTime)/1e3));
                p.addController(innerRadiusY);
            end
            
            function r = getInnerRadius(obj, time)
                r = obj.direction * obj.speed * time + obj.moveRadius - obj.widthPix;
                r = max(r, obj.minRadius - obj.widthPix);
                r = min(r, obj.maxRadius - obj.widthPix);
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.contrast = obj.contrastSeq( obj.numEpochsCompleted+1 );
            obj.direction = obj.directions( obj.numEpochsCompleted+1 );
            
            if obj.contrast > 0
                if obj.direction > 0
                    obj.sequence = 'expanding-light';
                else
                    obj.sequence = 'contracting-light';
                end
            else
                if obj.direction > 0
                    obj.sequence = 'expanding-dark';
                else
                    obj.sequence = 'contracting-dark';
                end
            end
            
            % Adjust the intensity based on the contrast.
            if obj.backgroundIntensity == 0
                obj.intensity = obj.contrast;
            else
                obj.intensity = obj.backgroundIntensity*obj.contrast + obj.backgroundIntensity;
            end 
            
            if obj.direction == 1
                obj.moveRadius = obj.minRadius;
                epoch.addParameter('direction', 'outward');
            else
                obj.moveRadius = obj.maxRadius;
                epoch.addParameter('direction', 'inward');
            end
            
            epoch.addParameter('intensity', obj.intensity);
            epoch.addParameter('contrast', obj.contrast);
            epoch.addParameter('sequence', obj.sequence);
        end
 
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end