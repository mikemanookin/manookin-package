classdef CamouflageBreak < edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 1500                 % Stimulus duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        waitTime = 1000
        backgroundSpeed = 250
        moveTime = 250
        moveSpeed = 1250
        barWidth = 50
        numObjectBars = 3
        contrastClass = 'gaussian'
        backgroundContrast = 1.0
        objectContrast = 1.0
        randomSeed = true               % Random or repeating seed
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular'         % Online analysis type.
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        numberOfAverages = uint16(40)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        contrastClassType = symphonyui.core.PropertyType('char','row',{'gaussian','binary','uniform'});
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        seed
        backgroundPosition
        objectPosition
        numFrames
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.manookin.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',[30 144 255]/255,...
                'groupBy',{'frameRate'});
            
            % Calculate the number of frames.
            obj.numFrames = ceil(obj.stimTime*1e-3*obj.frameRate); % Some extra so you don't throw error.
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Seed the random number generator.
            noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            % Generate the background texture.
            numBars = ceil(max(obj.canvasSize)*1.5/obj.barWidth);
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
            checkerboard.position = obj.canvasSize / 2 + obj.centerOffset;
            checkerboard.size = [numBars*obj.barWidth obj.canvasSize(2)];
            
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
            objectImg.position = obj.canvasSize / 2 + obj.centerOffset;
            objectImg.size = [obj.numObjectBars*obj.barWidth obj.canvasSize(2)];
            
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
                    p = obj.canvasSize / 2 + [obj.centerOffset(1) 0];
                else
                    fr = min(ceil(time*obj.frameRate), size(obj.backgroundPosition,1));
                    p = obj.backgroundPosition(fr,:);
                end
            end
            
            function p = getObjectPosition(obj, time)
                if time <= 0
                    p = obj.canvasSize / 2 + [obj.centerOffset(1) 0];
                else
                    fr = min(ceil(time*obj.frameRate), size(obj.objectPosition,1));
                    p = obj.objectPosition(fr,:);
                end
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Deal with the seed.
            if obj.randomSeed
                obj.seed = RandStream.shuffleSeed;
            else
                obj.seed = 1;
            end
            
            % Seed the random number generator.
            noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            % Get the background and object trajectories.
            obj.backgroundPosition = cumsum(obj.backgroundSpeed/obj.frameRate*noiseStream.randn(obj.numFrames,1))...
                *[1 0] + ones(obj.numFrames,1)*(obj.canvasSize/2+[obj.centerOffset(1) 0]);
            obj.objectPosition = obj.backgroundPosition;
            % Calculate the frame to start moving.
            mvFrame = floor(obj.waitTime * 1e-3 * obj.frameRate)+1;
            mvFrames = (1:length(mvFrame:obj.numFrames))*obj.moveSpeed/obj.frameRate;
            if obj.objectPosition(mvFrame) > (obj.canvasSize(1)/2 + obj.centerOffset(1))
                mvFrames = -mvFrames;
            end
            obj.objectPosition(mvFrame:obj.numFrames,1) = mvFrames' + obj.objectPosition(mvFrame-1,1);
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
        end
        
        % Same presentation each epoch in a run. Replay.
        function controllerDidStartHardware(obj)
            controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            if (obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < obj.numberOfAverages) && ~obj.randomSeed
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