classdef OrthoAnnulusAdapt < manookinlab.protocols.ManookinLabStageProtocol
    properties
        preTime = 250
        adaptTime = 2000
        waitTime = 100
        tailTime = 500
        adaptContrast = 1.0
        testContrasts = [-1.0 0 0.25 0.5 0.75 1.0]
        speed = 1000 % pix/sec
        width = 40
        minRadius = 40
        maxRadius = 160
        backgroundIntensity = 0.5 % (0-1)
        onlineAnalysis = 'extracellular'
        numberOfAverages = uint16(216)       % Number of epochs to queue
        amp
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthreshold', 'analog'})
        numRings
        tiltDirection
        direction
        contrast
        numStimFrames
        frameSequence
        noiseStream
        seed
        tiltDirections = {'none','outward','inward'}
        directions = [1,-1]
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
            
            obj.numRings = ceil((obj.maxRadiusPix - obj.widthPix) / obj.widthPix)+1;
            
            obj.numStimFrames = obj.adaptTime*1e-3*obj.frameRate + 15;
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create the adaptation sequence.
            
                % Generate the glider frame sequence.
            glider = [0 1 1; 1 1 0];
            obj.frameSequence = makeGlider(obj.numRings, 1, ...
                obj.numStimFrames, glider, 0, obj.seed);
            % Squeeze to two dimensions.
            obj.frameSequence = squeeze(obj.frameSequence);
            
            % Set the contrast.
            obj.frameSequence = obj.adaptContrast * (2 * obj.frameSequence - 1);
            % Convert to contrast.
            obj.frameSequence(obj.frameSequence <= 0) = obj.frameSequence(obj.frameSequence <= 0)*obj.backgroundIntensity + obj.backgroundIntensity;
            
            if strcmpi(obj.tiltDirection,'none') % No adaptation
                obj.frameSequence = obj.backgroundIntensity*ones(size(obj.frameSequence));
            end
            % Need to transpose at this point so that frames are rows.
            obj.frameSequence = obj.frameSequence';
            
            % Flip the frame sequence for outward tilt.
            if strcmp(obj.tiltDirection, 'inward')
                obj.frameSequence = fliplr(obj.frameSequence);
            end
            
            % Calculate the outer radii.
            radii = obj.maxRadiusPix - obj.widthPix*(0:obj.numRings-1);

            % Create the rings.
            for k = 1 : obj.numRings
                spot = stage.builtin.stimuli.Ellipse();
                spot.color = obj.backgroundIntensity;
                spot.radiusX = radii(k);
                spot.radiusY = radii(k);
                spot.position = obj.canvasSize/2;
                p.addStimulus(spot);

                spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.adaptTime) * 1e-3);
                p.addController(spotVisible);

                % Bar position controller
                spotColor = stage.builtin.controllers.PropertyController(spot, 'color', ...
                    @(state)frameSeq(obj, state.time - obj.preTime*1e-3, k));
                p.addController(spotColor);
            end
            
            function c = frameSeq(obj, time, whichSpot)
                if time >= 0 && time <= obj.adaptTime*1e-3
                    frame = floor(obj.frameRate * time) + 1;
                    c = obj.frameSequence(frame, whichSpot);
                else
                    c = obj.frameSequence(1, whichSpot);
                end
            end
            
            spot = stage.builtin.stimuli.Ellipse();
            spot.color = obj.contrast * obj.backgroundIntensity + obj.backgroundIntensity;
            spot.radiusX = 0;
            spot.radiusY = 0;
            spot.position = canvasSize/2;
            p.addStimulus(spot);
            
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= (obj.preTime+obj.adaptTime+obj.waitTime) * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            % Create a radius controller.
            maxRadiusPixX = stage.builtin.controllers.PropertyController(spot, 'radiusX',...
                @(state)getmaxRadiusPix(obj, state.time - (obj.preTime+obj.adaptTime+obj.waitTime)/1e3));
            p.addController(maxRadiusPixX);
            
            maxRadiusPixY = stage.builtin.controllers.PropertyController(spot, 'radiusY',...
                @(state)getmaxRadiusPix(obj, state.time - (obj.preTime+obj.adaptTime+obj.waitTime)/1e3));
            p.addController(maxRadiusPixY);
            
            function r = getmaxRadiusPix(obj, time)
                if time > 0 && time <= obj.stimTime*1e-3
                    if obj.direction > 0
                        r = obj.direction * obj.speed * time + obj.minRadiusPix;
                    else
                        r = obj.direction * obj.speed * time + obj.maxRadiusPix;
                    end
                    r = max(r, obj.minRadiusPix);
                    r = min(r, obj.maxRadiusPix);
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
            
            spotVisible = stage.builtin.controllers.PropertyController(mask, 'visible', ...
                @(state)state.time >= (obj.preTime+obj.adaptTime+obj.waitTime) * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);

            % Create a radius controller.
            innerRadiusX = stage.builtin.controllers.PropertyController(mask, 'radiusX',...
                @(state)getInnerRadius(obj, state.time - (obj.preTime+obj.adaptTime+obj.waitTime)/1e3));
            p.addController(innerRadiusX);

            innerRadiusY = stage.builtin.controllers.PropertyController(mask, 'radiusY',...
                @(state)getInnerRadius(obj, state.time - (obj.preTime+obj.adaptTime+obj.waitTime)/1e3));
            p.addController(innerRadiusY);
            
            function r = getInnerRadius(obj, time)
                if time >= 0 && time <= obj.stimTime*1e-3
                    if obj.direction > 0
                        r = obj.direction * obj.speed * time + obj.minRadiusPix - obj.widthPix;
                    else
                        r = obj.direction * obj.speed * time + obj.maxRadiusPix - obj.widthPix;
                    end
                    r = max(r, obj.minRadiusPix - obj.widthPix);
                    r = min(r, obj.maxRadiusPix - obj.widthPix);
                else
                    r = 0;
                end
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.direction = obj.directions(mod(obj.numEpochsCompleted,2)+1);
            % Tilt direction of adapting noise.
            obj.tiltDirection = obj.tiltDirections{mod(floor(obj.numEpochsCompleted/2), length(obj.tiltDirections))+1};
            % Test contrast.
            obj.contrast = obj.testContrasts(mod(floor(obj.numEpochsCompleted/(2*length(obj.tiltDirections))),...
                length(obj.testContrasts))+1);
            
            % Deal with the seed.
            obj.seed = RandStream.shuffleSeed;

            
            epoch.addParameter('seed', obj.seed);
            if obj.direction < 0
                epoch.addParameter('direction', 'inward');
            else
                epoch.addParameter('direction', 'outward');
            end
            epoch.addParameter('adaptationType',obj.tiltDirection);
            epoch.addParameter('contrast', obj.contrast);
            epoch.addParameter('widthPix', obj.widthPix);
            epoch.addParameter('minRadiusPix', obj.minRadiusPix);
            epoch.addParameter('maxRadiusPix', obj.maxRadiusPix);
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.adaptTime + obj.waitTime + 2*ceil((obj.maxRadiusPix-obj.minRadiusPix)/obj.speed*1e3);
        end
 
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end