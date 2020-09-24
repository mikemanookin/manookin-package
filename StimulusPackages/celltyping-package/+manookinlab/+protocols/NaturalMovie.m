classdef NaturalMovie < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Stimulus leading duration (ms)
        stimTime = 12000                % Stimulus duration (ms)
        tailTime = 500                  % Stimulus trailing duration (ms)
        maskDiameter = 0                % Mask diameter in microns
        apertureDiameters = [200,2000]  % Aperture diameter in microns.
        stimulusSet = 'CatCam'          % The current movie stimulus set
        onlineAnalysis = 'extracellular'% Type of online analysis
        numberOfAverages = uint16(108)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        apertureDiametersType = symphonyui.core.PropertyType('denserealdouble','matrix')
        imageMatrix
        backgroundFrame
        movieName
        magnificationFactor
        currentStimSet
        stimulusIndex
        pkgDir
        im
        apertureDiameter
        apertureDiameterPix
        backgroundIntensity        % Background light intensity (0-1)
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('manookinlab.figures.ResponseFigure', obj.rig.getDevices('Amp'), ...
                'numberOfAverages', obj.numberOfAverages);
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                colors = zeros(length(obj.apertureDiameters),3);
                colors(1,:) = [0.8,0,0];
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',colors,...
                    'groupBy',{'apertureDiameter'});
            end
            
            % Get the resources directory.
            obj.pkgDir = manookinlab.Package.getMoviePath();
            
            obj.currentStimSet = [obj.stimulusSet,'.mat'];
            
            % Load the current stimulus set.
            obj.im = load([obj.pkgDir,'\',obj.currentStimSet]);
            
            
            
            % Get the magnification factor. Exps were done with each pixel
            % = 1 arcmin == 1/60 degree; 200 um/degree...
            obj.magnificationFactor = round(2/60*200/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel'));
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create your scene.
            scene = stage.builtin.stimuli.Image(obj.imageMatrix(:,:,1));
            scene.size = [size(obj.imageMatrix,2) size(obj.imageMatrix,1)]*obj.magnificationFactor;
            scene.position = obj.canvasSize/2;
            
            scene.setMinFunction(GL.NEAREST);
            scene.setMagFunction(GL.NEAREST);
            
            % Add the stimulus to the presentation.
            p.addStimulus(scene);
            
            %apply eye trajectories to move image around
            scenePosition = stage.builtin.controllers.PropertyController(scene,...
                'imageMatrix', @(state)getScenePosition(obj, state.time - obj.preTime*1e-3));
            % Add the controller.
            p.addController(scenePosition);
            
            function p = getScenePosition(obj, time)
                if time > 0 && time <= obj.stimTime*1e-3
                    fr = round(time*60)+1;
                    p = obj.imageMatrix(:,:,fr);
                else 
                    p = obj.backgroundFrame;
                end
            end

            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);
            
            %--------------------------------------------------------------
            % Size is 0 to 1
            sz = (obj.apertureDiameterPix)/min(obj.canvasSize);
            % Create the outer mask.
            if sz < 1
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = obj.canvasSize/2;
                aperture.color = obj.backgroundIntensity;
                aperture.size = obj.canvasSize;
                [x,y] = meshgrid(linspace(-obj.canvasSize(1)/2,obj.canvasSize(1)/2,obj.canvasSize(1)), ...
                    linspace(-obj.canvasSize(2)/2,obj.canvasSize(2)/2,obj.canvasSize(2)));
                distanceMatrix = sqrt(x.^2 + y.^2);
                circle = uint8((distanceMatrix >= obj.apertureDiameterPix/2) * 255);
                mask = stage.core.Mask(circle);
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
            
            if (obj.maskDiameter > 0) % Create mask
                mask = stage.builtin.stimuli.Ellipse();
                mask.position = obj.canvasSize/2;
                mask.color = obj.backgroundIntensity;
                mask.radiusX = obj.maskDiameter/2/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
                mask.radiusY = obj.maskDiameter/2/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
                p.addStimulus(mask); %add mask
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.apertureDiameter = obj.apertureDiameters(mod(obj.numEpochsCompleted,length(obj.apertureDiameters)) + 1);
            obj.stimulusIndex = mod(floor(obj.numEpochsCompleted/length(obj.apertureDiameters)),obj.im.chunkCount) + 1;
            
            % Convert to pix.
            obj.apertureDiameterPix = round(obj.apertureDiameter/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel'));
            
            obj.movieName = obj.im.chunknames{obj.stimulusIndex};
            
            tmp = load([obj.pkgDir,'\',obj.stimulusSet,'\',obj.movieName,'.mat'],'M');
            obj.imageMatrix = tmp.M;
            
            obj.backgroundIntensity = mean(double(tmp.M(:))/255);
            obj.backgroundFrame = uint8(obj.backgroundIntensity*ones(240,320));
            
            % Save the parameters.
            epoch.addParameter('stimulusIndex', obj.stimulusIndex);
            epoch.addParameter('movieName', obj.movieName);
            epoch.addParameter('magnificationFactor', obj.magnificationFactor);
            epoch.addParameter('apertureDiameter',obj.apertureDiameter);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end