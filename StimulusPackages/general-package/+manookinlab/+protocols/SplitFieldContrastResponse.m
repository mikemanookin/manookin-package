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
%             obj.showFigure('edu.washington.riekelab.chris.figures.FrameTimingFigure',...
%                 obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            
%             if length(obj.stimSequence) > 1
%                 colors = edu.washington.riekelab.chris.utils.pmkmp(length(obj.stimSequence),'CubicYF');
%             else
%                 colors = [0 0 0];
%             end
            
%             obj.showFigure('edu.washington.riekelab.chris.figures.MeanResponseFigure',...
%                 obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis',...
%                 'groupBy',{'currentR1Contrast','currentR2Contrast'},...
%                 'sweepColor',colors);
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