classdef ContrastResponseFlash < edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 500                   % Spot leading duration (ms)
        stimTime = 500                  % Spot duration (ms)
        tailTime = 1500                 % Spot trailing duration (ms)
        waitTime = 0                    % Spot wait time (ms)
        contrasts = [0 1./[16 -16 16 -16 8 -8 8 -8 4 -4 2 -2 1.3333 -1.3333 1 -1]] % Contrast (-1:1)
        radius = 120                    % Inner radius in pixels.
        surroundContrasts = [-0.25 0 0.25]% Surround contrast
        surroundApertureRadius = 200    % Surround aperture radius (pix)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        chromaticClass = 'achromatic'   % Spot color
        stimulusClass = 'spot'          % Stimulus class
        onlineAnalysis = 'extracellular'% Online analysis type.
        numberOfAverages = uint16(51)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic', 'red', 'green', 'blue', 'yellow', 'L-iso', 'M-iso', 'S-iso', 'LM-iso'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus'})
        sequence
        contrast
        surroundContrast
    end
    
     % Analysis properties
    properties (Hidden)
        xaxis
        ctResponse
        repsPerX
        bgMean
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
            prepareRun@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            obj.showFigure('edu.washington.riekelab.manookin.figures.ContrastResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'preTime',obj.preTime+obj.waitTime,...
                'stimTime',obj.stimTime-obj.waitTime,...
                'contrasts',unique(obj.contrasts),...
                'temporalClass','pulse');
%                 'groupBy','surroundContrast',...
%                 'groupByValues',obj.surroundContrasts,...
%                 'temporalClass','pulse');
            
%             if ~strcmp(obj.onlineAnalysis, 'none')
%                 obj.analysisFigure = obj.showFigure('symphonyui.builtin.figures.CustomFigure', @obj.CRFanalysis);
%                 f = obj.analysisFigure.getFigureHandle();
%                 set(f, 'Name', 'Contrast Response Function');
%                 obj.analysisFigure.userData.axesHandle = axes('Parent', f);
%             end
            
            if strcmp(obj.stageClass, 'LightCrafter')
                obj.chromaticClass = 'achromatic';
            end
            
            obj.organizeParameters();
            
            obj.setColorWeights();
            obj.bgMean = 0;
        end
        
        function CRFanalysis(obj, ~, epoch)
            response = epoch.getResponse(obj.rig.getDevice(obj.amp));
            [y, ~] = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            
            % Calculate the pre- and stim-points.
            prePts = obj.preTime*1e-3*sampleRate;
            stimPts = obj.stimTime*1e-3*sampleRate;
            
            if strcmp(obj.onlineAnalysis,'extracellular')
                res = spikeDetectorOnline(y,[],sampleRate);
                y = zeros(size(y));
                if ~isempty(res.sp)
                    y(res.sp) = 1; %spike binary
                    y = psth(y, 10, sampleRate, 1);
                end;
                if prePts > 0
                    obj.bgMean = (obj.bgMean*sum(obj.repsPerX) + mean(y(1:prePts)))/(sum(obj.repsPerX)+1);
                else
                    obj.bgMean = 0;
                end
            else
                if prePts > 0
                    y = y - median(y(1:prePts));
                else
                    y = y - median(y);
                end
                obj.bgMean = 0;
            end
            
            %--------------------------------------------------------------
            % Get the response during the pulse.
            index = find(obj.xaxis == obj.contrast, 1);
            r = obj.ctResponse(index) * obj.repsPerX(index);
            r = r + mean(y(prePts+(1:stimPts)));
            
            % Increment the count.
            obj.repsPerX(index) = obj.repsPerX(index) + 1;
            obj.ctResponse(index) = r / obj.repsPerX(index);
            
            %--------------------------------------------------------------
            axesHandle = obj.analysisFigure.userData.axesHandle;
            cla(axesHandle);
            
            h1 = axesHandle;
            plot(obj.xaxis, obj.ctResponse-obj.bgMean, 'ko-', 'Parent', h1);
            set(h1, 'TickDir', 'out');
            ylabel(h1, 'response');
%             title(['Epoch ', num2str(obj.numEpochsCompleted), ' of ', num2str(obj.numberOfAverages)], 'Parent', h1);
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            spot = stage.builtin.stimuli.Ellipse();
            if strcmp(obj.stimulusClass, 'annulus')
                spot.radiusX = min(obj.canvasSize/2);
                spot.radiusY = min(obj.canvasSize/2);
            else
                spot.radiusX = obj.radius;
                spot.radiusY = obj.radius;
            end
            spot.position = obj.canvasSize/2 + obj.centerOffset;
            
            ct = obj.contrast;
            
            if strcmp(obj.stageClass, 'Video')
                spot.color = ct*obj.colorWeights*obj.backgroundIntensity + obj.backgroundIntensity;
            else
                spot.color = ct*obj.backgroundIntensity + obj.backgroundIntensity;
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Add an center mask if it's an annulus.
            if strcmp(obj.stimulusClass, 'annulus')
                mask = stage.builtin.stimuli.Ellipse();
                mask.radiusX = obj.radius;
                mask.radiusY = obj.radius;
                mask.position = obj.canvasSize/2 + obj.centerOffset;
                mask.color = obj.backgroundIntensity; 
                p.addStimulus(mask);
            elseif obj.surroundContrast ~= 0
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = obj.canvasSize/2 + obj.centerOffset;
                aperture.color = obj.surroundContrast*obj.backgroundIntensity + obj.backgroundIntensity;
                aperture.size = [max(obj.canvasSize) max(obj.canvasSize)];
                if obj.surroundApertureRadius > 0 && obj.surroundApertureRadius < min(obj.canvasSize/2)
                    mask = stage.core.Mask.createCircularAperture(obj.surroundApertureRadius*2/max(obj.canvasSize), 1024);
                    aperture.setMask(mask);
                end
                p.addStimulus(aperture);
                % Make the aperture visible only during the stimulus time.
                apertureVisible = stage.builtin.controllers.PropertyController(aperture, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time <= (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(apertureVisible);
            end
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= (obj.preTime+obj.waitTime) * 1e-3 && state.time <= (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);

        end
        
        % This is a method of organizing stimulus parameters.
        function organizeParameters(obj)
            
            % Create the matrix of bar positions.
            numReps = ceil(double(obj.numberOfAverages) / length(obj.contrasts));
            
            % Get the array of radii.
            ct = obj.contrasts(:) * ones(1, numReps);
            obj.sequence = ct(:)';  
            
            obj.xaxis = unique( obj.sequence );
            obj.ctResponse = zeros( size( obj.xaxis ) );
            obj.repsPerX = zeros( size( obj.xaxis ) );
        end
  
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current contrast.
            obj.contrast = obj.sequence( obj.numEpochsCompleted+1 );
            epoch.addParameter('contrast', obj.contrast);
            
            % Add the radius to the epoch.
            if strcmp(obj.stimulusClass, 'annulus')
                epoch.addParameter('outerRadius', min(obj.canvasSize/2));
                obj.surroundContrast = 0;
            else
                % Get the surround contrast.
                obj.surroundContrast = obj.surroundContrasts(mod(floor(obj.numEpochsCompleted/length(obj.contrasts)),length(obj.surroundContrasts))+1);
                epoch.addParameter('surroundContrast', obj.surroundContrast);
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