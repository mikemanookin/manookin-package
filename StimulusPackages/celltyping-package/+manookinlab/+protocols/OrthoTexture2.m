classdef OrthoTexture2 < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Texture leading duration (ms)
        tailTime = 250                  % Texture trailing duration (ms)
        waitTime = 2000                 % Time texture is presented before moving (ms)
        moveTime = 1000                 % Move duration (ms)
        contrasts = [0.05,0.1,0.2,0.4,0.8] % Texture contrast (0-1)
        spatialFrequencies = [2.0, 3.0] % Highest spatial frequencies in cyc/degree
        motionSpeeds = [1.0, 2.0]       % Texture approach speed (degrees/sec)
        changeClass = 'both'            % Type of change
        backgroundIntensity = 0.5       % Background light intensity (0-1)   
        onlineAnalysis = 'none'         % Type of online analysis
        numberOfAverages = uint16(400)  % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        changeClassType = symphonyui.core.PropertyType('char', 'row', {'both', 'optic flow', 'scale change'})
        spatialFrequenciesType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        contrastsType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        motionSpeedsType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        stimulusClasses = {'approaching','receding'}
        stimulusClass
        seed
        driftSpeedPix
        maxTextureSize
        textureFrames
        spatialFrequency
        textureSize
        textureFreqPix
        noiseStream
        contrast
        spatialFrequencyPix
        downsample = 10
        textureClasses
        textureClass
        motionSpeed
        classSequence
        contrastSequence
        frequencySequence
        speedSequence
        textureSequence
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
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if ~obj.isMeaRig
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                if ~strcmp(obj.onlineAnalysis, 'none')
                    colors = [0 0 0; 0.8 0 0; 0 0.7 0.2; 0 0.2 1];
                    obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                        obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                        'sweepColor',colors,...
                        'groupBy',{'stimulusClass'});
                end
            end
            
            if strcmp(obj.changeClass, 'both')
                obj.textureClasses = {'optic flow', 'scale change'};
            else
                obj.textureClasses = {obj.changeClass};
            end
            
            obj.driftSpeedPix = obj.rig.getDevice('Stage').um2pix(obj.motionSpeed);
            
            obj.textureSize = round(max(obj.canvasSize)/obj.downsample)*ones(1,2);
            
            % Organize the stimulus parameters.
            obj.organizeParameters();
        end
        
        
        function organizeParameters(obj)
            n_classes = length(obj.stimulusClasses);
            n_contrasts = length(obj.contrasts);
            n_frequencies = length(obj.spatialFrequencies);
            n_speeds = length(obj.motionSpeeds);
            n_textures = length(obj.textureClasses);
            n_reps = ceil(double(obj.numberOfAverages)/(n_classes*n_contrasts*n_frequencies*n_speeds*n_textures));
            
            obj.classSequence = repmat(obj.stimulusClasses,1,n_reps*n_contrasts*n_frequencies*n_speeds*n_textures);
            obj.contrastSequence = repmat(obj.contrasts,1,n_reps*n_classes*n_frequencies*n_speeds*n_textures);
            obj.frequencySequence = repmat(obj.spatialFrequencies,1,n_reps*n_classes*n_contrasts*n_speeds*n_textures);
            obj.speedSequence = repmat(obj.motionSpeeds,1,n_reps*n_classes*n_contrasts*n_frequencies*n_textures);
            obj.textureSequence = repmat(obj.textureClasses,1,n_reps*n_classes*n_contrasts*n_frequencies*n_speeds);
        end
        
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Generate the background texture.
            bground = stage.builtin.stimuli.Image(squeeze(obj.textureFrames(:,:,1)));
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
            
            % Remove the Amp responses if it's an MEA rig.
            if obj.isMeaRig
                amps = obj.rig.getDevices('Amp');
                for ii = 1:numel(amps)
                    if epoch.hasResponse(amps{ii})
                        epoch.removeResponse(amps{ii});
                    end
                    if epoch.hasStimulus(amps{ii})
                        epoch.removeStimulus(amps{ii});
                    end
                end
            end
            
            obj.stimulusClass = obj.classSequence{obj.numEpochsCompleted+1};
            obj.contrast = obj.contrastSequence(obj.numEpochsCompleted+1);
            obj.spatialFrequency = obj.frequencySequence(obj.numEpochsCompleted+1);
            obj.motionSpeed = obj.speedSequence(obj.numEpochsCompleted+1);
            obj.textureClass = obj.textureSequence{obj.numEpochsCompleted+1};
            
            epoch.addParameter('stimulusClass', obj.stimulusClass);
            epoch.addParameter('contrast', obj.contrast);
            epoch.addParameter('spatialFrequency', obj.spatialFrequency);
            epoch.addParameter('textureStdev', round(1./(obj.spatialFrequency/200*2)/2));
            epoch.addParameter('motionSpeed', obj.motionSpeed);
            epoch.addParameter('textureClass', obj.textureClass);
            
            if ( obj.numEpochsCompleted == 0 ) || ( mod(obj.numEpochsCompleted,2) == 0 )
                obj.seed = RandStream.shuffleSeed;
            end
            epoch.addParameter('seed', obj.seed);
            % Seed the random number generator.
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            obj.spatialFrequencyPix = obj.spatialFrequency * obj.rig.getDevice('Stage').um2pix(max(obj.canvasSize)) / 200 / obj.downsample;
            
            obj.textureFreqPix = obj.spatialFrequency / obj.rig.getDevice('Stage').um2pix(200);
            
            obj.generateTextures();
        end
        
        function generateTextures(obj)
            nx = obj.textureSize(1);
            ny = obj.textureSize(2);
            f0 = obj.spatialFrequency; %obj.spatialFrequency;
            
            [x,y] = meshgrid(-(nx):(nx-2));

            % Maximum spatial frequency in degrees.
%             maxF = obj.rig.getDevice('Stage').um2pix(max(obj.canvasSize)) / 200 / 2;
            maxF = max(obj.canvasSize) / obj.rig.getDevice('Stage').um2pix(200) / 2;
            disp(maxF)
            % in microns
            x = x / max(x(:)) * maxF;
            y = y / max(y(:)) * maxF;
            
            % Get the spatial frequencies.
            r = sqrt(x.^2 + y.^2);
%             r = sqrt((x/max(x(:))*maxF).^2 + (y/max(y(:))*maxF).^2);
            
            moveFrames = ceil(obj.moveTime * 1e-3 * obj.frameRate);
            
            if strcmp(obj.textureClass, 'optic flow')
                img = double( obj.noiseStream.rand(obj.textureSize) > 0.5 );
                fftI = fft2(2*img-1, 2*nx-1, 2*ny-1);
                fftI = fftshift( fftI );
            end

            M = zeros(nx, ny, moveFrames);
            fv = zeros(1,moveFrames);
            for k = 1 : moveFrames
                if strcmp(obj.textureClass, 'scale change')
                    img = double(obj.noiseStream.rand(obj.textureSize) > 0.5);
                    fftI = fft2(2*img-1,2*nx-1,2*ny-1);
                    fftI = fftshift(fftI);
                end
                
                t = (k-1)/obj.frameRate;
                f = exp(log(f0) - obj.motionSpeed*t);
                % Make sure you don't get NaN's. 
                if f < 0.05
                    f = 0.05;
                end
                fv(k) = f;
                tmp = obj.cosineFilter(fftI, r, f, nx, ny);
                tmp = tmp / std(tmp(:)); %tmp / max(abs(tmp(:)));
                tmp = manookinlab.util.makeUniformDist(tmp, 1);
                % Correct for Michaelson contrast
                ct = (max(tmp(:)) - min(tmp(:)))/(max(tmp(:))+min(tmp(:)));
                tmp = tmp / ct;
                M(:,:,k) = (obj.contrast * (2*tmp-1)) * obj.backgroundIntensity + obj.backgroundIntensity;
            end
            
%             M = (obj.contrast * M) * obj.backgroundIntensity + obj.backgroundIntensity;
            M = uint8(255 * M);
            
            if strcmpi(obj.stimulusClass, 'approaching')
                obj.textureFrames = M;
            else
                obj.textureFrames = M(:,:,end:-1:1);
            end
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
        function F = cosineFilter(fftI,r,peakFrequency,nx,ny)
            %F = cosineFilter(fftI,sf,f,nx,ny)
            %
            % INPUTS
            %   fftI
            %   sf: spatial frequencies
            %   f: peak frequency of the bandpass filter
            %   nx
            %   ny

%             bpfun = @(w)(0.5 + 0.5 * cos(w));
            
            sf = r;
            sf(r > peakFrequency) = peakFrequency - (sf(r > peakFrequency)-peakFrequency);
            sf(sf < 0) = 0;
            sf = sf/peakFrequency;
            foo = -sf*pi/2+pi/2;

%             foo = log2(sf/(2*f));
%             foo(foo > pi) = pi;
%             foo(foo < -pi) = -pi;

%             myFilter = bpfun((foo));
            myFilter = cos(foo);
            myFilter(nx+1,ny+1) = 0; % Zero out the F0/DC offset.
            F = fftI.*myFilter;
            F = ifftshift(F);
            F = ifft2(F,2*nx-1,2*ny-1);
            F = real(F(1:nx,1:ny));
        end
    end
end