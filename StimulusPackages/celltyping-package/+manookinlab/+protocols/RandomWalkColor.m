classdef RandomWalkColor < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 200                   % Stimulus leading duration (ms)
        moveTime = 30000                 % Stimulus duration (ms)
        tailTime = 200                  % Stimulus trailing duration (ms)
        waitTime = 1000                 % Stimulus wait duration (ms)
        stimulusClass = 'bar'
        stimulusDiameter = 200              % Spot diameter in microns
        contrasts = [-0.5,0.5]      % Spot contrasts
        stimulusSpeed = 500 % Spot speed (std) in microns/second
        chromaticClass = 'achromatic'
        backgroundIntensity = 0.5
        repeatingSeed = false
        onlineAnalysis = 'none'% Type of online analysis
        numberOfAverages = uint16(48)   % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        contrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','blue','yellow'})
        stimulusIndicesType = symphonyui.core.PropertyType('denserealdouble','matrix')
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'bar','spot'})
        spotRadiusPix
        contrast
        stimulusSpeedPix
        spotPositions
        backgroundConditions
        backgroundCondition
        seed
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.ResponseFigure', obj.rig.getDevices('Amp'), ...
                    'numberOfAverages', obj.numberOfAverages);

                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',[0 0 0]);
            end
            
            % Get the spot diameter in pixels.
            obj.spotRadiusPix = obj.stimulusDiameter / 2 / obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            % Motion per frame
            obj.stimulusSpeedPix = obj.stimulusSpeed / 60 / obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            
            obj.seed = 1;
            
            if strcmp(obj.chromaticClass, 'achromatic')
                obj.backgroundConditions = {'stationary','motion-gaussian','motion-gaussian'};
            else
                obj.backgroundConditions = {'stationary','motion-natural','motion-natural'};
            end
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            if strcmp(obj.stimulusClass,'bar')
                spot = stage.builtin.stimuli.Rectangle();
                spot.size = [obj.canvasSize(1), obj.spotRadiusPix*2];
                spot.position = obj.canvasSize/2;
                spot.orientation = 0;
                spot.color = obj.backgroundIntensity*obj.contrast + obj.backgroundIntensity; 
            else
                % Add the spots.
                spot = stage.builtin.stimuli.Ellipse();
                spot.radiusX = obj.spotRadiusPix;
                spot.radiusY = obj.spotRadiusPix;
                spot.position = obj.canvasSize/2;
                spot.color = obj.backgroundIntensity*obj.contrast + obj.backgroundIntensity; 
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            if strcmp(obj.stimulusClass,'bar')
                spotPosition = stage.builtin.controllers.PropertyController(spot,...
                    'position', @(state)getBarPosition(obj, state.frame - ceil((obj.preTime+obj.waitTime)/1e3*60)));
            else
                spotPosition = stage.builtin.controllers.PropertyController(spot,...
                    'position', @(state)getSpotPosition(obj, state.frame - ceil((obj.preTime+obj.waitTime)/1e3*60)));
            end
            p.addController(spotPosition);
            
            function p = getBarPosition(obj, frame)
                if frame > 0 
                    p = [0,obj.spotPositions(frame,2)]+obj.canvasSize/2;
                else
                    p = obj.canvasSize/2;
                end
            end
            
            function p = getSpotPosition(obj, frame)
                if frame > 0 
                    p = obj.spotPositions(frame,:)+obj.canvasSize/2;
                else
                    p = obj.canvasSize/2;
                end
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.backgroundCondition = obj.backgroundConditions{mod(obj.numEpochsCompleted,length(obj.backgroundConditions))+1};
            
            if obj.repeatingSeed
                obj.seed = 1;
            else
                seedIdx = mod(obj.numEpochsCompleted,length(obj.contrasts)*length(obj.backgroundConditions))+1;
                if seedIdx == 1
                    obj.seed = RandStream.shuffleSeed;
                end
            end
            
            obj.spotPositions = manookinlab.util.getHMMTrajectory2d(obj.stimTime*1e-3+2, obj.seed, 'motionSpeed', obj.stimulusSpeed);
            % Get the spot contrast.
            obj.contrast = obj.contrasts(mod(floor(obj.numEpochsCompleted/length(obj.backgroundConditions)),length(obj.contrasts))+1);
            
            % Save the parameters.
            epoch.addParameter('contrast',obj.contrast);
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('backgroundCondition',obj.backgroundCondition)
            epoch.addParameter('spotX',obj.spotPositions(:,1)');
            epoch.addParameter('spotY',obj.spotPositions(:,2)');
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.waitTime + obj.moveTime;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end