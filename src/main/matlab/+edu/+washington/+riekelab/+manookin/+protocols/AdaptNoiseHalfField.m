classdef AdaptNoiseHalfField < edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stim leading duration (ms)
        stimTime = 15000                % Stim duration (ms)
        tailTime = 250                  % Stim trailing duration (ms)
        lowContrast = 1/3               % Low-contrast value (0-1)
        highContrast = 1.0              % High-contrast value (0-1)
        highDuration = 5000             % High-contrast duration (ms)
        radius = 150                    % Inner radius in pixels.
        separationPix = 32              % Separation between RF regions (pix)
        orientation = 0                 % Stimulus orientiation (degrees)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        noiseClass = 'binary-gaussian'  % Noise type (binary or Gaussian)
        chromaticClass = 'achromatic'   % Chromatic class
        onlineAnalysis = 'extracellular'% Online analysis type.
        randomSeed = true               % Use random noise seed?
        numberOfAverages = uint16(30)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary','gaussian','binary-gaussian'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        seed
        bkg
        noiseStream
        frameSeq1
        frameSeq2
        stimulusClasses = {'normal','adapt-interact','adapt-single','normal','adapt-interact','adapt-single'};
        lowFields = {'left','left','left','right','right','right'};
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj);
            
            colors = pmkmp(3, 'IsoL');
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));            
            obj.showFigure('edu.washington.riekelab.manookin.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'stimulusClass'});
            
            if obj.backgroundIntensity == 0
                obj.bkg = 0.5;
            else
                obj.bkg = obj.backgroundIntensity;
            end
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Calculate the orientation in radians.
            orientationRads = obj.orientation/180*pi;
            
            % Make the two rectangles.
            rect1 = stage.builtin.stimuli.Rectangle();
            rect1.size = [obj.radius 2*obj.radius];
            rect1.orientation = obj.orientation;
            rect1.position = obj.canvasSize/2 + obj.centerOffset + [cos(orientationRads) sin(orientationRads)] .* (-obj.radius/2*ones(1,2));
            rect1.color = obj.bkg;
            
            rect2 = stage.builtin.stimuli.Rectangle();
            rect2.size = [obj.radius 2*obj.radius];
            rect2.orientation = obj.orientation;
            rect2.position = obj.canvasSize/2 + obj.centerOffset + [cos(orientationRads) sin(orientationRads)] .* (obj.radius/2*ones(1,2));
            rect2.color = obj.bkg;
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect1);
            p.addStimulus(rect2);
            
            if obj.separationPix > 0
                maskRect = stage.builtin.stimuli.Rectangle();
                maskRect.size = [obj.separationPix 2*obj.radius];
                maskRect.orientation = obj.orientation;
                maskRect.position = obj.canvasSize/2 + obj.centerOffset;
                maskRect.color = obj.bkg;
                p.addStimulus(maskRect);
            end
            
            % Add a surround mask
            if obj.radius < min(obj.canvasSize)
                mask = stage.builtin.stimuli.Rectangle();
                mask.color = obj.backgroundIntensity;
                mask.position = obj.canvasSize/2 + obj.centerOffset;
                mask.orientation = 0;
                mask.size = max(obj.canvasSize) * ones(1,2);
                sc = obj.radius*2 / max(obj.canvasSize);
                m = stage.core.Mask.createCircularAperture(sc);
                mask.setMask(m);
                p.addStimulus(mask);
            end
            
            % Control when the rectangles are visible.
            rect1Visible = stage.builtin.controllers.PropertyController(rect1, 'visible', ...
                @(state)state.time > obj.preTime * 1e-3 && state.time <= (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(rect1Visible);
            rect2Visible = stage.builtin.controllers.PropertyController(rect2, 'visible', ...
                @(state)state.time > obj.preTime * 1e-3 && state.time <= (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(rect2Visible);
            
            % Color controllers for the rectangles.
            color1Controller = stage.builtin.controllers.PropertyController(rect1, 'color', ...
                @(state)getRect1(obj, state.time - obj.preTime * 1e-3));
            p.addController(color1Controller);
            
            color2Controller = stage.builtin.controllers.PropertyController(rect2, 'color', ...
                @(state)getRect2(obj, state.time - obj.preTime * 1e-3));
            p.addController(color2Controller);
            
            function c = getRect1(obj, time)
                if time > 0 && time <= obj.stimTime*1e-3
                    c = obj.frameSeq1(floor(time*obj.frameRate)+1);
                else
                    c = obj.bkg;
                end
            end
            
            function c = getRect2(obj, time)
                if time > 0 && time <= obj.stimTime*1e-3
                    c = obj.frameSeq2(floor(time*obj.frameRate)+1);
                else
                    c = obj.bkg;
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
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            % Pre-generate frames for the epoch.
            nframes = obj.stimTime*1e-3*obj.frameRate + 15;
            if strcmp(obj.noiseClass,'binary')
                frameSeq = obj.noiseStream.rand(1,nframes) > 0.5;
                frameSeq = 2*frameSeq - 1;
            else
                frameSeq = 0.3*obj.noiseStream.randn(1,nframes);
            end
            eFrames = floor(obj.highDuration*1e-3*obj.frameRate);
            
            stimulusClass = obj.stimulusClasses{mod(obj.numEpochsCompleted,length(obj.stimulusClasses))+1};
            lowField = obj.lowFields{mod(obj.numEpochsCompleted,length(obj.lowFields))+1};
            
            if strcmp(obj.noiseClass,'binary-gaussian') && ~strcmp(stimulusClass,'normal')
                frameSeq(1:eFrames) = 2*(frameSeq(1:eFrames) > 0) - 1;
            end
            
            if strcmp(stimulusClass,'normal')
                if strcmp(lowField, 'left')
                    obj.frameSeq1 = obj.lowContrast*frameSeq;
                    obj.frameSeq2 = zeros(1,nframes);
                else
                    obj.frameSeq2 = obj.lowContrast*frameSeq;
                    obj.frameSeq1 = zeros(1,nframes);
                end
            elseif strcmp(stimulusClass,'adapt-interact')
                if strcmp(lowField, 'left')
                    obj.frameSeq1 = obj.lowContrast*frameSeq;
                    obj.frameSeq1(1:eFrames) = 0;
                    obj.frameSeq2 = zeros(1,nframes);
                    obj.frameSeq2(1:eFrames) = obj.highContrast*frameSeq(1:eFrames);
                else
                    obj.frameSeq2 = obj.lowContrast*frameSeq;
                    obj.frameSeq2(1:eFrames) = 0;
                    obj.frameSeq1 = zeros(1,nframes);
                    obj.frameSeq1(1:eFrames) = obj.highContrast*frameSeq(1:eFrames);
                end
            else
                if strcmp(lowField, 'left')
                    obj.frameSeq1 = obj.lowContrast*frameSeq;
                    obj.frameSeq1(1:eFrames) = obj.highContrast*frameSeq(1:eFrames);
                    obj.frameSeq2 = zeros(1,nframes);
                else
                    obj.frameSeq2 = obj.lowContrast*frameSeq;
                    obj.frameSeq2(1:eFrames) = obj.highContrast*frameSeq(1:eFrames);
                    obj.frameSeq1 = zeros(1,nframes);
                end
            end
            
            % Convert to LED contrast.
            obj.frameSeq1 = obj.bkg*obj.frameSeq1 + obj.bkg;
            obj.frameSeq2 = obj.bkg*obj.frameSeq2 + obj.bkg;
            
            % Save the seed.
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('stimulusClass',stimulusClass);
            epoch.addParameter('lowField', lowField);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
    end
    
end