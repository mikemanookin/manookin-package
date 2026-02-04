classdef SplitFieldContrastResponse < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    properties
        apertureDiameter = 300   % um (center spot)
        
        backgroundIntensity = 0.5  % 0-1, background and gap intensity
        contrasts = [-1.0 -0.5 -0.25 0 0.25 0.5 1]  % contrast for dark bars
        
        preTime = 100   % ms
        stimTime = 200  % ms
        tailTime = 200  % ms
        rotation = 0    % 0 or 90
        onlineAnalysis = 'extracellular'

        numberOfAverages = uint16(3)  % number of repeats to queue
        amp
    end
    
    properties(Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        currentR1Contrast
        currentR2Contrast
        stimSequence
    end
    
    properties (Hidden, Transient)
        analysisFigure
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            % Create stimulus sequence combining all parameters
            obj.stimSequence = [];
            for bc1 = 1:length(obj.contrasts)
                for bc2 = 1:length(obj.contrasts)
                    obj.stimSequence = [obj.stimSequence; ...
                        obj.contrasts(bc1), obj.contrasts(bc2)];
                end
            end
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            if exist('edu.washington.riekelab.chris.figures.FrameTimingFigure','class')
                obj.showFigure('edu.washington.riekelab.chris.figures.FrameTimingFigure',...
                    obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            else
                obj.showFigure('edu.washington.riekelab.figures.FrameTimingFigure', obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            end
            
            if exist('edu.washington.riekelab.chris.figures.FrameTimingFigure','class')
                if length(obj.stimSequence) > 1
                    colors = edu.washington.riekelab.chris.utils.pmkmp(length(obj.stimSequence),'CubicYF');
                else
                    colors = [0 0 0];
                end

                obj.showFigure('edu.washington.riekelab.chris.figures.MeanResponseFigure',...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis',...
                    'groupBy',{'currentR1Contrast','currentR2Contrast'},...
                    'sweepColor',colors);
            else
                if length(obj.stimSequence) > 1
                    colors = manookinlab.util.pmkmp(length(obj.stimSequence),'CubicYF');
                else
                    colors = [30 144 255]/255;
                end
                if strcmpi(obj.onlineAnalysis,'extracellular')
                    use_psth = true;
                else
                    use_psth = false;
                end
                obj.showFigure('edu.washington.riekelab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'psth',use_psth,...
                    'sweepColor',colors,...
                    'groupBy',{'currentR1Contrast','currentR2Contrast'});
            end
            
            if ~strcmp(obj.onlineAnalysis,'none')
                % custom figure handler
                if isempty(obj.analysisFigure) || ~isvalid(obj.analysisFigure)
                    obj.analysisFigure = obj.showFigure('symphonyui.builtin.figures.CustomFigure', @obj.CRF_GRID);
                    f = obj.analysisFigure.getFigureHandle();
                    set(f, 'Name', 'Contrast grid');
                    obj.analysisFigure.userData.runningTrace = zeros(length(obj.contrasts));
                    obj.analysisFigure.userData.axesHandle = axes('Parent', f);
                else
                    obj.analysisFigure.userData.runningTrace = zeros(length(obj.contrasts));
                end
            end
        end
        
        function CRF_GRID(obj, ~, epoch) %online analysis function
            response = epoch.getResponse(obj.rig.getDevice(obj.amp));
            quantities = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            
            pre_pts = floor(sampleRate*obj.preTime*1e-3);
            stim_pts = floor(sampleRate*obj.stimTime*1e-3);
            
            axesHandle = obj.analysisFigure.userData.axesHandle;
            runningTrace = obj.analysisFigure.userData.runningTrace;
            
            if strcmp(obj.onlineAnalysis,'extracellular') %spike recording
                filterSigma = (20/1000)*sampleRate; %msec -> dataPts
                newFilt = normpdf(1:10*filterSigma,10*filterSigma/2,filterSigma);
                res = edu.washington.riekelab.util.spikeDetectorOnline(quantities, [], sampleRate);
                epochResponseTrace = zeros(size(quantities));
                epochResponseTrace(res.sp) = 1; %spike binary
                epochResponseTrace = sampleRate*conv(epochResponseTrace,newFilt,'same'); %inst firing rate
            else %intracellular - Vclamp
                epochResponseTrace = quantities-mean(quantities(1:sampleRate*obj.preTime/1000)); %baseline
                if strcmp(obj.onlineAnalysis,'exc') %measuring exc
                    epochResponseTrace = epochResponseTrace./(-60-0); %conductance (nS), ballpark
                elseif strcmp(obj.onlineAnalysis,'inh') %measuring inh
                    epochResponseTrace = epochResponseTrace./(0-(-60)); %conductance (nS), ballpark
                end
            end
            
            epoch_response = mean(epochResponseTrace(pre_pts+(1:stim_pts))) - mean(epochResponseTrace(1:pre_pts));
            x_index = find(obj.contrasts == obj.currentR1Contrast,1);
            y_index = find(obj.contrasts == obj.currentR2Contrast,1);
            
            runningTrace(x_index,y_index) = runningTrace(x_index,y_index) + epoch_response;
            cla(axesHandle);
            h = surf(obj.contrasts,obj.contrasts,runningTrace, 'Parent', axesHandle);
            set(h,'FaceColor','flat');
            view(axesHandle,[45,45]);
%             h = line(timeVector, runningTrace./obj.numEpochsCompleted, 'Parent', axesHandle);
%             set(h,'Color',[0 0 0],'LineWidth',2);
            xlabel(axesHandle,'R1 contrast');
            ylabel(axesHandle,'R2 contrast');
            title(axesHandle,'Running response average...')
            if strcmp(obj.onlineAnalysis,'extracellular')
                ylabel(axesHandle,'Spike rate (Hz)')
            else
                ylabel(axesHandle,'Resp (nS)')
            end
            obj.analysisFigure.userData.runningTrace = runningTrace;
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            % Determine current stimulus parameters
            stimIndex = mod(obj.numEpochsCompleted, size(obj.stimSequence, 1)) + 1;
            obj.currentR1Contrast = obj.stimSequence(stimIndex, 1);
            obj.currentR2Contrast = obj.stimSequence(stimIndex, 2);
            
            epoch.addParameter('currentR1Contrast', obj.currentR1Contrast);
            epoch.addParameter('currentR2Contrast', obj.currentR2Contrast);
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            
            % Create the annular grating image
            gratingImage = obj.createGrating(canvasSize, apertureDiameterPix);
            
            % Display grating as image stimulus
            scene = stage.builtin.stimuli.Image(gratingImage);
            scene.size = canvasSize;
            scene.position = canvasSize/2;
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);
            p.addStimulus(scene);
            
            % Control visibility during stimTime only
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);
            
        end
        
        function gratingImage = createGrating(obj, canvasSize, apertureDiameterPix)
            
            % Create coordinate system
            [x, y] = meshgrid(linspace(-canvasSize(1)/2, canvasSize(1)/2, canvasSize(1)), ...
                              linspace(-canvasSize(2)/2, canvasSize(2)/2, canvasSize(2)));
            
            % Create square wave grating
            if (obj.rotation == 0)
                grating = sign(sin(2*pi*x/apertureDiameterPix));
            else
                grating = sign(sin(2*pi*y/apertureDiameterPix));
            end
                
            % Apply contrasts to bright and dark bars
            brightBars = (grating > 0);
            darkBars = (grating <= 0);
            
            gratingImage = obj.backgroundIntensity * ones(size(grating));
            gratingImage(brightBars) = obj.backgroundIntensity * (1 + obj.currentR1Contrast);
            gratingImage(darkBars) = obj.backgroundIntensity * (1 + obj.currentR2Contrast);
            
            % Create mask
            [x, y] = meshgrid(linspace(-canvasSize(1)/2, canvasSize(1)/2, canvasSize(1)), ...
                              linspace(-canvasSize(2)/2, canvasSize(2)/2, canvasSize(2)));
            r = sqrt(x.^2 + y.^2);
            
            apertureMask = (r <= apertureDiameterPix/2);
            
            % Apply mask: grating in annulus, background elsewhere
            finalImage = obj.backgroundIntensity * ones(size(gratingImage));
            finalImage(apertureMask) = gratingImage(apertureMask);
            
            % Check for out of range values and warn
            if max(finalImage(:)) > 1 || min(finalImage(:)) < 0
                warning('Image intensity out of range: max = %.3f, min = %.3f', ...
                    max(finalImage(:)), min(finalImage(:)));
            end
            
            % Convert to uint8
            gratingImage = uint8(finalImage * 255);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages * size(obj.stimSequence, 1);
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages * size(obj.stimSequence, 1);
        end
    end
end