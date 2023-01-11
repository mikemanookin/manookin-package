classdef NaturalImageFlash < edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol

    properties
        preTime = 200 % ms
        flashTime = 200 % ms
        tailTime = 200 % ms

        apertureDiameter = 200 % um

        numberOfAverages = uint16(180) % number of epochs to queue
    end
    
    properties (Hidden)
        %saved out to each epoch...
        imagePatchIndex
        currentPatchLocation
    end

    properties (Dependent)
        stimTime
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
            prepareRun@edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol(obj);

            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
            end
            
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis);
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.flashTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);

            if numel(obj.rig.getDeviceNames('Amp')) >= 2
                epoch.addResponse(obj.rig.getDevice(obj.amp2));
            end
            
            %pull patch location:
            obj.imagePatchIndex = mod(obj.numEpochsCompleted,obj.noPatches) + 1;
            obj.currentPatchLocation(1) = obj.patchLocations(1,obj.imagePatchIndex); %in VH pixels
            obj.currentPatchLocation(2) = obj.patchLocations(2,obj.imagePatchIndex);
            
            obj.imagePatchMatrix = ...
                edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol.getImagePatchMatrix(...
                obj, obj.currentPatchLocation);

            epoch.addParameter('imagePatchIndex', obj.imagePatchIndex);
            epoch.addParameter('currentPatchLocation', obj.currentPatchLocation);
        end
        
        function p = createPresentation(obj)            
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.flashTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            
            %make image stim:
            scene = stage.builtin.stimuli.Image(obj.imagePatchMatrix);
            scene.size = canvasSize; %scale up to canvas size
            scene.position = canvasSize/2;
            % Use linear interpolation when scaling the image.
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);
            p.addStimulus(scene);
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.flashTime) * 1e-3);
            p.addController(sceneVisible);

            if (obj.apertureDiameter > 0) %% Create aperture
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2;
                aperture.color = obj.backgroundIntensity;
                aperture.size = [max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createCircularAperture(apertureDiameterPix/max(canvasSize), 1024); %circular aperture
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = (obj.preTime + obj.flashTime + obj.tailTime);
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
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

    end
    
end