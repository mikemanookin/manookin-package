classdef CamouflageBreak2 < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        waitTime = 3000                 % Time prior to break/move (ms)
        moveTime = 250                  % Duration of move (ms)
        stopTime = 3000                 % Time following break/move (ms)
        directions = 'right'             % Object direction(s) to probe.
        backgroundSpeeds = [0,500] % Background speed in microns/sec
        moveSpeeds = [500,1000] % Foreground motion speeds in microns/sec
        barWidth = 50                   % Bar width in microns
        numObjectBars = 4
        contrastClass = 'gaussian'
        backgroundContrast = 1.0
        objectContrast = 1.0
        randomSeed = true               % Random or repeating seed
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular'         % Online analysis type.
        numberOfAverages = uint16(100)   % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Hidden)
        ampType
        contrastClassType = symphonyui.core.PropertyType('char','row',{'gaussian','binary','uniform'});
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        moveSpeedsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        backgroundSpeedsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        directionsType = symphonyui.core.PropertyType('char', 'row', {'random', 'both', 'right', 'left'})
        seed
        backgroundPosition
        objectPosition
        moveFrames
        numFrames
        barWidthPix
        moveSpeed
        backgroundSpeedPix
        moveSpeedPix
        backgroundSpeed
        direction
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                co = get(groot, 'defaultAxesColorOrder');
                
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',co,...
                    'groupBy',{'moveSpeed'});
            end
            
            % Calculate the number of frames.
            obj.numFrames = ceil(obj.stimTime*1e-3*obj.frameRate); % Some extra so you don't throw error.
            obj.moveFrames = round(obj.moveTime*1e-3*obj.frameRate);
            obj.barWidthPix = obj.rig.getDevice('Stage').um2pix(obj.barWidth);
            
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Seed the random number generator.
            noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            % Generate the background texture.
            numBars = ceil(max(obj.canvasSize)*1.5/obj.barWidthPix);
            switch obj.contrastClass
                case 'binary'
                    imageMatrix = obj.backgroundContrast*(2*(noiseStream.rand(1,numBars)>0.5)-1);
                    objectMatrix = obj.backgroundContrast*(2*(noiseStream.rand(1,obj.numObjectBars)>0.5)-1);
                case 'uniform'
                    imageMatrix = obj.backgroundContrast*(2*noiseStream.rand(1,numBars)-1);
                    objectMatrix = obj.backgroundContrast*(2*noiseStream.rand(1,obj.numObjectBars)-1);
                otherwise
                    imageMatrix = obj.backgroundContrast*0.3*noiseStream.randn(1,numBars);
                    objectMatrix = obj.backgroundContrast*0.3*noiseStream.randn(1,obj.numObjectBars);
            end
            if obj.backgroundIntensity > 0
                imageMatrix = obj.backgroundIntensity * imageMatrix + obj.backgroundIntensity;
                objectMatrix = obj.backgroundIntensity * objectMatrix + obj.backgroundIntensity;
            else
                imageMatrix = 0.5 * imageMatrix + 0.5;
                objectMatrix = 0.5 * objectMatrix + 0.5;
            end
            % Convert to 8-bit
            imageMatrix = uint8(imageMatrix * 255);
            objectMatrix = uint8(objectMatrix * 255);
            
            %--------------------------------------------------------------
            % Create your background image.
            checkerboard = stage.builtin.stimuli.Image(imageMatrix);
            checkerboard.position = obj.canvasSize / 2;
            checkerboard.size = [numBars*obj.barWidthPix obj.canvasSize(2)];
            
            % Set the minifying and magnifying functions to form discrete
            % stixels.
            checkerboard.setMinFunction(GL.NEAREST);
            checkerboard.setMagFunction(GL.NEAREST);
            
            % Add the stimulus to the presentation.
            p.addStimulus(checkerboard);
            
            gridVisible = stage.builtin.controllers.PropertyController(checkerboard, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(gridVisible);
            
            bgPosition = stage.builtin.controllers.PropertyController(checkerboard,...
                'position', @(state)getBackgroundPosition(obj, state.time - obj.preTime*1e-3));
            % Add the controller.
            p.addController(bgPosition);
            
            %--------------------------------------------------------------
            % Create your background image.
            objectImg = stage.builtin.stimuli.Image(objectMatrix);
            objectImg.position = obj.canvasSize / 2;
            objectImg.size = [obj.numObjectBars*obj.barWidthPix obj.canvasSize(2)];
            
            % Set the minifying and magnifying functions to form discrete
            % stixels.
            objectImg.setMinFunction(GL.NEAREST);
            objectImg.setMagFunction(GL.NEAREST);
            
            % Add the stimulus to the presentation.
            p.addStimulus(objectImg);
            
            objectVisible = stage.builtin.controllers.PropertyController(objectImg, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(objectVisible);
            
            objPosition = stage.builtin.controllers.PropertyController(objectImg,...
                'position', @(state)getObjectPosition(obj, state.time - obj.preTime*1e-3));
            % Add the controller.
            p.addController(objPosition);

            function p = getBackgroundPosition(obj, time)
                if time <= 0
                    p = obj.canvasSize / 2;
                else
                    fr = min(ceil(time*obj.frameRate), size(obj.backgroundPosition,1));
                    p = obj.backgroundPosition(fr,:);
                end
            end
            
            function p = getObjectPosition(obj, time)
                if time <= 0
                    p = obj.canvasSize / 2;
                else
                    fr = min(ceil(time*obj.frameRate), size(obj.objectPosition,1));
                    p = obj.objectPosition(fr,:);
                end
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the background motion speed.
            obj.backgroundSpeed = obj.backgroundSpeeds(mod(floor(obj.numEpochsCompleted/length(obj.moveSpeeds)), length(obj.backgroundSpeeds))+1);
%             obj.backgroundSpeed = obj.backgroundSpeeds(mod(obj.numEpochsCompleted, length(obj.backgroundSpeeds))+1);
            epoch.addParameter('backgroundSpeed',obj.backgroundSpeed);
            
            % Get the object motion speed.
            obj.moveSpeed = obj.moveSpeeds(mod(obj.numEpochsCompleted, length(obj.moveSpeeds))+1);
%             obj.moveSpeed = obj.moveSpeeds(mod(floor(obj.numEpochsCompleted/length(obj.backgroundSpeeds)), length(obj.moveSpeeds))+1);
            epoch.addParameter('moveSpeed',obj.moveSpeed);
            
            % Get object motion speed in pixels per second.
            obj.moveSpeedPix = obj.rig.getDevice('Stage').um2pix(obj.moveSpeed);
            obj.backgroundSpeedPix = obj.rig.getDevice('Stage').um2pix(obj.backgroundSpeed);
            
            % Deal with the seed.
            if obj.randomSeed
                obj.seed = RandStream.shuffleSeed;
            else
                obj.seed = 1;
            end
            
            % Seed the random number generator.
            noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            % Get the background and object trajectories.
            obj.backgroundPosition = cumsum(obj.backgroundSpeedPix/obj.frameRate*noiseStream.randn(obj.numFrames,1))...
                *[1 0] + ones(obj.numFrames,1)*(obj.canvasSize/2);
            obj.objectPosition = obj.backgroundPosition;
            % Calculate the frame to start moving.
            mvFrame = floor(obj.waitTime * 1e-3 * obj.frameRate)+1;
            mvFrames = (1:length(mvFrame+(1:obj.moveFrames)))*obj.moveSpeedPix/obj.frameRate;
            if strcmp(obj.directions, 'left') || (strcmp(obj.directions, 'both') && (mod(floor(obj.numEpochsCompleted/2)) == 0)
                obj.direction = 'left';
                mvFrames = -mvFrames;
            elseif strcmp(obj.directions, 'random') 
                if obj.objectPosition(mvFrame) > (obj.canvasSize(1)/2)
                    obj.direction = 'left';
                    mvFrames = -mvFrames;
                else
                    obj.direction = 'right';
                end
            else
                obj.direction = 'right';
            end
            obj.objectPosition(mvFrame+(1:obj.moveFrames),1) = mvFrames' + obj.objectPosition(mvFrame-1,1);
            obj.objectPosition(mvFrame+obj.moveFrames+1:obj.numFrames,1) = mvFrames(end) + obj.objectPosition(mvFrame+obj.moveFrames+1:obj.numFrames,1);
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('direction',obj.direction);
        end
        
        % Same presentation each epoch in a run. Replay.
        function controllerDidStartHardware(obj)
            controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            if (obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < obj.numberOfAverages) && ~obj.randomSeed...
                    && length(obj.backgroundSpeeds)==1 && length(obj.moveSpeeds)==1
                obj.rig.getDevice('Stage').replay
            else
                obj.rig.getDevice('Stage').play(obj.createPresentation());
            end
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.waitTime + obj.moveTime + obj.stopTime;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
