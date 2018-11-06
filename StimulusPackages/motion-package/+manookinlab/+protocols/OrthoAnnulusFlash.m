classdef OrthoAnnulusFlash < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp
        preTime = 500
        stimTime = 100
        tailTime = 900
        contrasts = [-1,1]
        width = 40 % um
        minRadius = 40 % um
        maxRadius = 120 % um
        backgroundIntensity = 0.5 % (0-1)
        spatialClass = 'annulus'
        onlineAnalysis = 'extracellular'
        numberOfAverages = uint16(100) % number of epochs to queue
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthreshold', 'analog'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'annulus','spot','grating'})
        intensity
        innerRadius
        outerRadius
        contrast
        radii
        widthPix
        minRadiusPix
        maxRadiusPix
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
            
            % Get the color sequence for plotting.
            colors = zeros(1,3);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'contrast'});
            
            % Convert from microns to pixels.
            device = obj.rig.getDevice('Stage');
            obj.widthPix = device.um2pix(obj.width);
            obj.minRadiusPix = device.um2pix(obj.minRadius);
            obj.maxRadiusPix = device.um2pix(obj.maxRadius);
            
            % Define the radii.
            numRadii = ceil(2*(obj.maxRadiusPix-obj.minRadiusPix)/obj.widthPix) + 1;
            obj.radii = linspace(obj.minRadiusPix,obj.maxRadiusPix,numRadii);
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            spot = stage.builtin.stimuli.Ellipse();
            spot.color = obj.intensity;
            spot.radiusX = obj.outerRadius;
            spot.radiusY = obj.outerRadius;
            spot.position = canvasSize/2;
            p.addStimulus(spot);
            
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            if strcmp(obj.spatialClass, 'annulus')
                % Create the mask spot.
                mask = stage.builtin.stimuli.Ellipse();
                mask.color = obj.backgroundIntensity;
                mask.radiusX = obj.innerRadius;
                mask.radiusY = obj.innerRadius;
                mask.position = canvasSize/2;
                p.addStimulus(mask);
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current radius.
            obj.outerRadius = obj.radii( mod(floor(obj.numEpochsCompleted/length(obj.contrasts)), length(obj.radii)) + 1 );
            obj.innerRadius = obj.outerRadius - obj.widthPix;
            if obj.innerRadius < 0
                obj.innerRadius = 0;
            end
            % Set the current contrast.
            obj.contrast = obj.contrasts( mod(obj.numEpochsCompleted,length(obj.contrasts))+1 );
            
            % Adjust the intensity based on the contrast.
            if obj.backgroundIntensity == 0
                obj.intensity = obj.contrast;
            else
                obj.intensity = obj.backgroundIntensity*obj.contrast + obj.backgroundIntensity;
            end 
            
            epoch.addParameter('intensity', obj.intensity);
            epoch.addParameter('contrast', obj.contrast);
            epoch.addParameter('innerRadius', obj.innerRadius);
            epoch.addParameter('outerRadius', obj.outerRadius);
        end
 
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end