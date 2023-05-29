classdef MovingBarColorAdapt < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Bar leading duration (ms)
        stimTime = 2500                 % Bar duration (ms)
        tailTime = 500                  % Bar trailing duration (ms)
        orientations = 0:30:330         % Bar angle (deg)
        speed = 1000                    % Bar speed (mu/sec)
        contrasts = [-0.3,0.3] % Bar ontrast (-1:1)
        barSize = [200, 4000]           % Bar size (x,y) in microns
        chromaticClass = 'chromatic'
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        innerMaskRadius = 0             % Inner mask radius in microns.
        outerMaskRadius = 0             % Outer mask radius in microns.
        randomOrder = true              % Random orientation order?
        onlineAnalysis = 'none'         % Online analysis type.
        numberOfAverages = uint16(32)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        orientationsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        contrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'chromatic','achromatic'})
        barColorType = symphonyui.core.PropertyType('char', 'row', {'gray','blue','yellow'})
        backgroundColorType = symphonyui.core.PropertyType('char', 'row', {'gray','blue','yellow','blue-gray','yellow-gray'})
        barColor
        backgroundColor
        backgroundColors
        barColors
        sequence
        orientation
        orientationRads
        barSizePix
        innerMaskRadiusPix
        outerMaskRadiusPix
        speedPix
        contrast
        barRGB
        backgroundRGB
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.barSizePix = obj.rig.getDevice('Stage').um2pix(obj.barSize);
            obj.innerMaskRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.innerMaskRadius);
            obj.outerMaskRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.outerMaskRadius);
            obj.speedPix = obj.rig.getDevice('Stage').um2pix(obj.speed);
            
            if strcmp(obj.chromaticClass, 'chromatic')
                obj.backgroundColors = {'gray','blue-gray','yellow-gray','blue-gray','yellow-gray'};
                obj.barColors = {'matched','matched','matched','gray','gray'};
            else
                obj.backgroundColors = {'gray'};
                obj.barColors = {'matched'};
            end
            
            if length(obj.orientations) > 1
                colors = pmkmp(length(obj.orientations),'CubicYF');
            else
                colors = zeros(1,3);
            end
            
            if ~strcmp(obj.onlineAnalysis, 'none')
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'orientation'});
            end
            
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                if length(unique(obj.orientations)) > 1
                    obj.showFigure('manookinlab.figures.DirectionFigure', ...
                        obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                        'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                        'orientations', unique(obj.orientations));
                else
                    obj.showFigure('manookinlab.figures.ContrastResponseFigure', ...
                        obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                        'preTime',obj.preTime,...
                        'stimTime',obj.stimTime,...
                        'contrasts',unique(obj.contrasts),...
                        'temporalClass','pulse');
                end
            end
            
            % Get the frame rate. Need to check if it's a LCR rig.
            if ~isempty(strfind(obj.rig.getDevice('Stage').name, 'LightCrafter'))
                obj.frameRate = obj.rig.getDevice('Stage').getPatternRate();
            else
                obj.frameRate = obj.rig.getDevice('Stage').getMonitorRefreshRate();
            end
            
            % Get the canvas size.
            obj.canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            
            % Check the outer mask radius.
            if obj.outerMaskRadiusPix > min(obj.canvasSize/2)
                obj.outerMaskRadiusPix = min(obj.canvasSize/2);
            elseif obj.outerMaskRadiusPix <= 0
                obj.outerMaskRadiusPix = max(obj.canvasSize/2);
            end
            
            obj.organizeParameters();
 
        end
        
        function rgb = getRGB(~,colorName)
            switch colorName
                case 'blue'
                    rgb = [0,0,1];
                case 'blue-gray'
                    rgb = [0.5,0.5,1];
                case 'yellow'
                    rgb = [1,1,0];
                case 'yellow-gray'
                    rgb = [1,1,0.5];
                otherwise
                    rgb = ones(1,3);
            end
        end
        
        function organizeParameters(obj)
            % Calculate the number of repetitions of each annulus type.
            numReps = ceil(double(obj.numberOfAverages) / length(obj.orientations));
            
            % Set the sequence.
            if obj.randomOrder
                obj.sequence = zeros(length(obj.orientations), numReps);
                for k = 1 : numReps
                    obj.sequence(:,k) = obj.orientations(randperm(length(obj.orientations)));
                end
            else
                obj.sequence = obj.orientations(:) * ones(1, numReps);
            end
            obj.sequence = obj.sequence(:)';
            obj.sequence = obj.sequence(1 : obj.numberOfAverages);
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity*ones(1,3));
            
            % Set the background rectangle.
            bg_rect = stage.builtin.stimuli.Rectangle();
            bg_rect.size = obj.canvasSize;
            bg_rect.position = obj.canvasSize/2;
            bg_rect.orientation = 0;
            bg_rect.color = obj.backgroundRGB;
            % Add the stimulus to the presentation.
            p.addStimulus(bg_rect);
            
            bgVisible = stage.builtin.controllers.PropertyController(bg_rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(bgVisible);
            
            
            % Set the bar color.
            colorTmp = obj.contrast*obj.barRGB*obj.backgroundIntensity+obj.backgroundIntensity;
            colorTmp(obj.barRGB == 0) = 0;
            
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.barSizePix;
            rect.position = obj.canvasSize/2;
            rect.orientation = obj.orientation;
            rect.color = colorTmp;
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect);
            
            barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(barVisible);
            
            % Bar position controller
            barPosition = stage.builtin.controllers.PropertyController(rect, 'position', ...
                @(state)motionTable(obj, state.time - obj.preTime*1e-3));
            p.addController(barPosition);
            
            function p = motionTable(obj, time)
                % Calculate the increment with time.  
                inc = time * obj.speedPix - obj.outerMaskRadiusPix - obj.barSizePix(1)/2 ;
                
                p = [cos(obj.orientationRads) sin(obj.orientationRads)] .* (inc*ones(1,2)) + obj.canvasSize/2;
            end
            
            % Create the inner mask.
            if (obj.innerMaskRadiusPix > 0)
                p.addStimulus(obj.makeInnerMask());
            end
            
            % Create the outer mask.
            if (obj.outerMaskRadius > 0)
                p.addStimulus(obj.makeOuterMask());
            end
        end
        
        function mask = makeOuterMask(obj)
            mask = stage.builtin.stimuli.Rectangle();
            mask.color = obj.backgroundRGB;
            mask.position = obj.canvasSize/2;
            mask.orientation = 0;
            mask.size = 2 * max(obj.canvasSize) * ones(1,2);
            sc = obj.outerMaskRadiusPix*2 / (2*max(obj.canvasSize));
            m = stage.core.Mask.createCircularAperture(sc);
            mask.setMask(m);
        end
        
        function mask = makeInnerMask(obj)
            mask = stage.builtin.stimuli.Ellipse();
            mask.radiusX = obj.innerMaskRadiusPix;
            mask.radiusY = obj.innerMaskRadiusPix;
            mask.color = obj.backgroundRGB;
            mask.position = obj.canvasSize/2;
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the bar contrast.
            obj.contrast = obj.contrasts(mod(floor(obj.numEpochsCompleted/length(obj.orientations)), length(obj.contrasts))+1);
            obj.backgroundColor = obj.backgroundColors{mod(floor(obj.numEpochsCompleted/length(obj.contrasts)), length(obj.backgroundColors))+1};
            obj.barColor = obj.barColors(mod(floor(obj.numEpochsCompleted/length(obj.contrasts)), length(obj.barColors))+1);
            
            % Set the bar and background contrasts.
            if strcmp(obj.barColor,'matched')
                obj.barRGB = obj.getRGB(obj.backgroundColor);
            else
                obj.barRGB = obj.getRGB('gray');
            end
            obj.backgroundRGB = (obj.getRGB(obj.backgroundColor)-1)*obj.backgroundIntensity+obj.backgroundIntensity;
            
            % Get the current bar orientation.
            obj.orientation = obj.sequence(obj.numEpochsCompleted+1);
            obj.orientationRads = obj.orientation / 180 * pi;
            
            epoch.addParameter('orientation', obj.orientation);
            epoch.addParameter('contrast',obj.contrast);
            epoch.addParameter('backgroundColor',obj.backgroundColor);
            epoch.addParameter('barColor',obj.barColor);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
