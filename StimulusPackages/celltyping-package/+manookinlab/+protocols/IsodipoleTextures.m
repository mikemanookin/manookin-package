classdef IsodipoleTextures < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp % Output amplifier
        preTime     = 250 % in ms
        stimTime    = 250 % in ms
        tailTime    = 100 % in ms
        checkSize = 30 % Length of check edge in microns
        contrast = 1.0 % Texture contrast (0-1)
        randomSeed = true % Whether to use a random seed to generate the textures.
        backgroundIntensity = 0.5; % 0 - 1 (corresponds to image intensities in folder)
        onlineAnalysis = 'none'
        numberOfAverages = uint16(7) % number of epochs to queue 
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        texture_classes = {'2-positive','2-negative','3-positive','3-negative','even','odd','random'};
        texture_class
        noiseStream
        sequence
        seed
        numXChecks
        numYChecks
        current_image
        image_sequence
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)

            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            % Get the grid size.
            gridSizePix = obj.checkSize/(10000.0/obj.rig.getDevice('Stage').um2pix(10000.0));
            obj.numXChecks = ceil(obj.canvasSize(1)/gridSizePix);
            obj.numYChecks = ceil(obj.canvasSize(2)/gridSizePix);
            
            num_reps = ceil(double(obj.numberOfAverages)/length(obj.texture_classes));
            obj.image_sequence = zeros(1,obj.numberOfAverages);
            for ii = 1 : num_reps
                seq = randperm(length(obj.texture_classes));
                obj.image_sequence((ii-1)*length(seq)+(1:length(seq))) = seq;
            end
            obj.image_sequence = obj.image_sequence(1:obj.numberOfAverages);
        end

        
        function p = createPresentation(obj)
            
            % Stage presets
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();     
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            
            % Rotate image
            p.setBackgroundColor(obj.backgroundIntensity)   % Set background intensity
            
            % Prep to display image
            scene = stage.builtin.stimuli.Image(uint8(obj.current_image));
            scene.size = [canvasSize(1),canvasSize(2)];
            scene.position = canvasSize/2;
            
            % Use linear interpolation when scaling the image
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);

            % Only allow image to be visible during specific time
            p.addStimulus(scene);
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            % Get the textir class.
            seq = obj.image_sequence(obj.numEpochsCompleted+1);
            obj.texture_class = obj.texture_classes{seq};
            
            % Deal with the seed.
            if obj.randomSeed
                obj.seed = RandStream.shuffleSeed;
            else
                obj.seed = 1;
            end
            
            % Seed the random number generator.
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            % Make the texture
            obj.make_texture();
            
            epoch.addParameter('seed',obj.seed);
            epoch.addParameter('texture_class',obj.texture_class);
        end
        
        function make_texture(obj)
            switch obj.texture_class
                case '2-positive'
                    obj.current_image = obj.generateDoubleTexture(0);
                case '2-negative'
                    obj.current_image = obj.generateDoubleTexture(1);
                case '3-positive'
                    obj.current_image = obj.generateTripleTexture([0 1 1; 1 1 1; 1 1 0],1);
                case '3-negative'
                    obj.current_image = obj.generateTripleTexture([0 1 1; 1 1 1; 1 1 0],0);
                case '3-positive converging'
                    obj.current_image = obj.generateTripleTexture([0 0 0; 1 0 0; 1 0 1],1);
                case '3-negative converging'
                    obj.current_image = obj.generateTripleTexture([0 0 0; 1 0 0; 1 0 1],0);
                case 'even'
                    obj.current_image = obj.generateTexture(0,0);
                case 'odd'
                    obj.current_image = obj.generateTexture(1,0);
                case 'random'
                    obj.current_image = obj.generateRandomTexture(1);
            end
            obj.current_image = obj.contrast * (2*obj.current_image - 1);
            obj.current_image = 255*(obj.backgroundIntensity*obj.current_image + obj.backgroundIntensity);
        end
        
        function texture = generateTexture(obj, fprop, fspor) 
            % Generate the texture.
            texture = repmat((obj.noiseStream.rand(1,obj.numXChecks)>0.5),obj.numYChecks,1)...
                +repmat(obj.noiseStream.rand(obj.numYChecks,1)>0.5,1,obj.numXChecks);
            % Add decorrelation.
            texture = mod(texture+cumsum(cumsum((...
                obj.noiseStream.rand(obj.numYChecks,obj.numXChecks)<fprop)),2)+...
                (obj.noiseStream.rand(obj.numYChecks,obj.numXChecks)<fspor),2);
        end
        
        function texture = generateDoubleTexture(obj, parity)
            texture = manookinlab.util.makeGlider(obj.numYChecks, 1, obj.numXChecks, ...
                    [0 1 1; 1 1 0], parity, obj.seed);
            texture = squeeze(texture);
        end
        
        function texture = generateTripleTexture(obj, glider, parity)
            texture = manookinlab.util.makeGlider(obj.numYChecks, 1, obj.numXChecks, ...
                    glider, parity, obj.seed);
            texture = squeeze(texture);
        end
        
        function texture = generateRandomTexture(obj, parity)
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed + 1);
            texture = obj.noiseStream.rand(obj.numYChecks, obj.numXChecks);
            if parity == 0
                texture = (texture > 0.5027);
            else
                texture = (texture > 0.5);
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
