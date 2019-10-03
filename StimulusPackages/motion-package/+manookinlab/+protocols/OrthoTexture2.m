classdef OrthoTexture2 < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Texture leading duration (ms)
        tailTime = 250                  % Texture trailing duration (ms)
        waitTime = 2000                 % Time texture is presented before moving (ms)
        moveTime = 1000                 % Move duration (ms)
        contrast = 1.0                  % Texture contrast (0-1)
        spatialFrequencies = [3,1.5,0.75,0.375] % Spatial frequencies in cyc/degree
        textureStdev = 15               % Texture standard deviation (microns)
        moveSpeed = 2.0                 % Texture approach speed (degrees/sec)
        backgroundIntensity = 0.5       % Background light intensity (0-1)   
        onlineAnalysis = 'extracellular' % Type of online analysis
        numberOfAverages = uint16(100)  % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        spatialFrequenciesType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        stimulusClasses = {'approaching','receding'}
        stimulusClass
        seed
        textureStdevPix
        driftSpeedPix
        maxTextureSize
        textureFrames
        spatialFrequency
        textureSize
        textureFreqPix
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
                colors = [0 0 0; 0.8 0 0; 0 0.7 0.2; 0 0.2 1];
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',colors,...
                    'groupBy',{'stimulusClass'});
            end
            
            obj.textureStdevPix = obj.rig.getDevice('Stage').um2pix(obj.textureStdev);
            obj.driftSpeedPix = obj.rig.getDevice('Stage').um2pix(obj.moveSpeed);
            
            downsample = 5;
            obj.textureSize = round(max(obj.canvasSize)/downsample)*ones(1,2);
        end
        
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Generate the background texture.
            bground = stage.builtin.stimuli.Image(obj.backgroundTexture);
            bground.position = obj.canvasSize / 2;
            bground.size = max(obj.canvasSize)*ones(1,2);

            % Set the minifying and magnifying functions to form discrete
            % stixels.
            bground.setMinFunction(GL.NEAREST);
            bground.setMagFunction(GL.NEAREST);
            
            % Add the stimulus to the presentation.
            p.addStimulus(bground);
            
            % Make the grating visible only during the stimulus time.
            backgroundVisible = stage.builtin.controllers.PropertyController(bground, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(backgroundVisible);
            
            bgController = stage.builtin.controllers.PropertyController(bground, 'imageMatrix',...
                @(state)approachTrajectory(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
            p.addController(bgController);

            %--------------------------------------------------------------
            % Control the texture values.
            function p = approachTrajectory(obj, time)
                if time > 0 && time <= obj.moveTime*1e-3
                    frame = min(floor(time*obj.frameRate)+1,size(obj.textureFrames,3));
                    p = squeeze(obj.textureFrames(:,:,frame));
                elseif time <= 0
                    p = squeeze(obj.textureFrames(:,:,1));
                else
                    p = squeeze(obj.textureFrames(:,:,end));
                end
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.stimulusClass = obj.stimulusClasses{mod(obj.numEpochsCompleted,length(obj.stimulusClasses))+1};
            epoch.addParameter('stimulusClass', obj.stimulusClass);
            
            % Get the spatial frequency.
            obj.spatialFrequency = obj.spatialFrequencies(mod(floor(obj.numEpochsCompleted/length(obj.stimulusClasses)),length(obj.spatialFrequencies))+1);
            epoch.addParameter('spatialFrequency', obj.spatialFrequency);
            epoch.addParameter('textureStdev',1./(obj.spatialFrequency/200*2)/2);
            
            % Deal with the seed.
            if obj.useRandomSeed
                obj.seed = RandStream.shuffleSeed;
            else
                obj.seed = 1;
            end
            epoch.addParameter('seed', obj.seed);
            
            obj.textureFreqPix = obj.spatialFrequency / obj.rig.getDevice('Stage').um2pix(200);
            
            obj.generateTextures();
        end
        
        function generateTextures(obj)
            nx = obj.textureSize(1);
            ny = obj.textureSize(2);
            f0 = obj.spatialFrequency;
            downsample = 5;
            
            [x,y] = meshgrid(-(nx):(nx-2));
            % in microns
            x = x * downsample / 2;
            y = y * downsample / 2;

            % Size of single cycle in degrees.
            maxF = obj.rig.getDevice('Stage').um2pix(200) / (downsample/2);
            maxF = sqrt(2*(maxF^2));
            % Get the spatial frequencies.
            r = sqrt((x/max(x(:))*maxF).^2 + (y/max(y(:))*maxF).^2);
            
            moveFrames = ceil(obj.moveTime / obj.moveSpeed * obj.frameRate);
            img = noiseStream.rand(obj.textureSize);
            fftI = fft2(2*img-1,2*nx-1,2*ny-1);
            fftI = fftshift(fftI);

            M = zeros(nx, ny, moveFrames);
            fv = zeros(1,moveFrames);
            for k = 1 : moveFrames
                t = (k-1)/obj.frameRate;
                f = exp(log(f0) - obj.moveSpeed*t);
                % Make sure you don't get NaN's. 
                if f < 0.05
                    f = 0.05;
                end
                fv(k) = f;
                tmp = obj.cosineFilter(fftI, r, f, nx, ny);
                tmp = 0.3 * tmp / std(tmp(:)); %tmp / max(abs(tmp(:)));
                M(:,:,k) = tmp;
            end
            
            M = (obj.contrast * M) * obj.backgroundIntensity + obj.backgroundIntensity;
            M = uint8(255 * M);
            
            if strcmpi(obj.stimulusClass, 'approaching')
                obj.textureFrames = M;
            else
                obj.textureFrames = M(:,:,end:-1:1);
            end
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
    
    methods (Static)
        function F = cosineFilter(fftI,sf,f,nx,ny)
            %F = cosineFilter(fftI,sf,f,nx,ny)
            %
            % INPUTS
            %   fftI
            %   sf: spatial frequencies
            %   f: peak frequency of the bandpass filter
            %   nx
            %   ny

            bpfun = @(w)(0.5 + 0.5 * cos(w));

            foo = log2(sf/(2*f));
            foo(foo > pi) = pi;
            foo(foo < -pi) = -pi;

            myFilter = bpfun((foo));
            myFilter(nx+1,ny+1) = 0; % Zero out the F0/DC offset.
            F = fftI.*myFilter;
            F = ifftshift(F);
            F = ifft2(F,2*nx-1,2*ny-1);
            F = real(F(1:nx,1:ny));
        end
    end
end 