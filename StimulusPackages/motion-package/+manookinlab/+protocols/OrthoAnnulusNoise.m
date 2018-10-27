classdef OrthoAnnulusNoise < manookinlab.protocols.ManookinLabStageProtocol
    properties
        preTime = 250
        stimTime = 10000
        tailTime = 250
        contrast = 1
        width = 40
        minRadius = 40
        maxRadius = 160
        randsPerRep = 8                     % Number of random seeds per repeat
        backgroundIntensity = 0.5 % (0-1)
        onlineAnalysis = 'extracellular'
        distributionClass = 'gaussian'      % Distribution type: gaussian or uniform
        numberOfAverages = uint16(50)       % Number of epochs to queue
        amp
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthreshold', 'analog'})
        distributionClassType = symphonyui.core.PropertyType('char','row',{'gaussian', 'uniform'})
        radii
        widthPix
        minRadiusPix
        maxRadiusPix
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
                'groupBy',{'frameRate'});
            
            % Convert from microns to pixels.
            device = obj.rig.getDevice('Stage');
            obj.widthPix = device.um2pix(obj.width);
            obj.minRadiusPix = device.um2pix(obj.minRadius);
            obj.maxRadiusPix = device.um2pix(obj.maxRadius);
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            spot = stage.builtin.stimuli.Ellipse();
            spot.color = obj.contrast * obj.backgroundIntensity + obj.backgroundIntensity;
            spot.radiusX = 0;
            spot.radiusY = 0;
            spot.position = canvasSize/2;
            p.addStimulus(spot);
            
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            % Create a radius controller.
            outerRadiusX = stage.builtin.controllers.PropertyController(spot, 'radiusX',...
                @(state)getOuterRadius(obj, state.time - obj.preTime/1e3));
            p.addController(outerRadiusX);
            
            outerRadiusY = stage.builtin.controllers.PropertyController(spot, 'radiusY',...
                @(state)getOuterRadius(obj, state.time - obj.preTime/1e3));
            p.addController(outerRadiusY);
            
            function r = getOuterRadius(obj, time)
                if time > 0 && time <= obj.stimTime*1e-3
                    r = obj.radii(floor(time*obj.frameRate)+1);
                else
                    r = 0;
                end
            end
            
            % Create the mask spot.
            mask = stage.builtin.stimuli.Ellipse();
            mask.color = obj.backgroundIntensity;
            mask.radiusX = 0;
            mask.radiusY = 0;
            mask.position = canvasSize/2;
            p.addStimulus(mask);

            % Create a radius controller.
            innerRadiusX = stage.builtin.controllers.PropertyController(mask, 'radiusX',...
                @(state)getInnerRadius(obj, state.time - obj.preTime/1e3));
            p.addController(innerRadiusX);

            innerRadiusY = stage.builtin.controllers.PropertyController(mask, 'radiusY',...
                @(state)getInnerRadius(obj, state.time - obj.preTime/1e3));
            p.addController(innerRadiusY);
            
            function r = getInnerRadius(obj, time)
                if time > 0 && time <= obj.stimTime*1e-3
                    r = obj.radii(floor(time*obj.frameRate)+1) - obj.widthPix;
                else
                    r = 0;
                end
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Deal with the seed.
            if obj.randsPerRep > 0 && (mod(obj.numEpochsCompleted+1,obj.randsPerRep+1) == 0)
                seed = 1;
            else
                seed = RandStream.shuffleSeed;
            end
            
            % Seed the random number generator.
            noiseStream = RandStream('mt19937ar', 'Seed', seed);
            
            % Get the outer radii. Gaussian distribution.
            nframes = obj.stimTime*1e-3*obj.frameRate + 15; 
            
            if strcmpi(obj.distributionClass, 'gaussian')
                obj.radii = 0.5*(0.3*noiseStream.randn(1, nframes))+0.5;
                obj.radii(obj.radii < 0) = 0; 
                obj.radii(obj.radii > 1) = 1;
                obj.radii = (obj.maxRadiusPix-obj.minRadiusPix)*obj.radii+obj.minRadiusPix;
            else
                obj.radii = (obj.maxRadiusPix-obj.minRadiusPix)*noiseStream.rand(1, nframes)+obj.minRadiusPix;
            end
            obj.radii = round(obj.radii);
            
            epoch.addParameter('seed', seed);
            epoch.addParameter('radii', obj.radii);
            epoch.addParameter('widthPix', obj.widthPix);
            epoch.addParameter('minRadiusPix', obj.minRadiusPix);
            epoch.addParameter('maxRadiusPix', obj.maxRadiusPix);
        end
 
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end