classdef TinySpot < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stim leading duration (ms)
        tailTime = 750                  % Stim trailing duration (ms)
        modulationContrasts = [0 1]     % Flash 1 contrast (-1:1)
        modulationDuration = 1000       % Flash 1 duration (ms)
        modulationFrequency = 30.0      % Modulation temporal frequency (Hz)
        flash2Contrasts = [0 0.125 0.25 0.5 0.75 1] % Test flash contrasts (-1:1)
        flash2Duration = 100            % Test flash duration
        ipis = [50 50]                  % Inter-pulse intervals (ms)
        radius = 25                     % Inner radius in pixels.
        apertureRadius = 105            % Blank aperture radius (pix)
        backgroundIntensity = 0.1         % Background light intensity (0-1)
        modulationClass = 'full-field'  % Adapting flash class
        flash2Class = 'spot'            % Test flash class
        chromaticClass = 'achromatic'   % Chromatic class
        backgroundChromaticClass = 'achromatic' % Background chromatic class.
        onlineAnalysis = 'extracellular'% Online analysis type.
        numberOfAverages = uint16(240)   % Number of epochs
    end
    
    properties (Dependent) 
        stimTime
    end
    
    properties (Hidden)
        ampType
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','red-green isoluminant','red-green isochromatic'})
        backgroundChromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','red-green isoluminant','red-green isochromatic'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        modulationClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus', 'full-field'})
        flash2ClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus', 'full-field'})
        modulationContrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        flash2ContrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        bkg
        modulationContrast
        flash2Contrast
        ipi
        rgbMeans
        rgbValues
        backgroundMeans
        bkgValues
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
                obj.showFigure('manookinlab.figures.AdaptFlashFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'preTime',obj.preTime,...
                    'flash1Duration',obj.modulationDuration,...
                    'flash2Duration',obj.flash2Duration,...
                    'flash1Contrasts',unique(obj.modulationContrasts),...
                    'flash2Contrasts',unique(obj.flash2Contrasts),...
                    'ipis',obj.ipis);
            end
            
            if obj.backgroundIntensity == 0
                obj.bkg = 0.5;
            else
                obj.bkg = obj.backgroundIntensity;
            end
            
            if strcmp(obj.stageClass,'LightCrafter')
                obj.chromaticClass = 'achromatic';
            end
            
            % Check the color space.
            if strcmp(obj.chromaticClass,'achromatic') && strcmp(obj.backgroundChromaticClass,'achromatic')
                obj.rgbMeans = obj.bkg;
                obj.rgbValues = 1;
                obj.backgroundMeans = obj.bkg*ones(1,3);
                obj.bkgValues = 1;
            elseif ~strcmp(obj.chromaticClass,'achromatic') && ~strcmp(obj.backgroundChromaticClass,'achromatic')
                [obj.rgbMeans, ~, obj.rgbValues] = getMaxContrast(obj.quantalCatch, obj.chromaticClass);
                [obj.backgroundMeans, ~, obj.bkgValues] = getMaxContrast(obj.quantalCatch, obj.backgroundChromaticClass);
                obj.backgroundMeans = obj.backgroundMeans(:)' * obj.bkg/0.5;
                obj.rgbMeans = obj.rgbMeans * obj.bkg/0.5;
            elseif strcmp(obj.backgroundChromaticClass,'achromatic')
                [obj.rgbMeans, ~, obj.rgbValues] = getMaxContrast(obj.quantalCatch, obj.chromaticClass);
                obj.rgbMeans = obj.rgbMeans * obj.bkg/0.5;
                obj.backgroundMeans = obj.rgbMeans;
                obj.bkgValues = 1;
            else
                [obj.backgroundMeans, ~, obj.bkgValues] = getMaxContrast(obj.quantalCatch, obj.backgroundChromaticClass);
                obj.backgroundMeans = obj.backgroundMeans(:)' * obj.bkg/0.5;
                obj.rgbMeans = obj.backgroundMeans;
                obj.rgbValues = 1;
            end
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            if obj.modulationContrast > 0 || obj.backgroundIntensity > 0
            if strcmp(obj.modulationClass, 'spot')
                modulation = stage.builtin.stimuli.Ellipse();
                modulation.radiusX = obj.radius;
                modulation.radiusY = obj.radius; 
                modulation.position = obj.canvasSize/2;
            else
                modulation = stage.builtin.stimuli.Rectangle();
                modulation.position = obj.canvasSize/2;
                modulation.orientation = 0;
                modulation.size = max(obj.canvasSize) * ones(1,2);
                if strcmp(obj.modulationClass, 'annulus')
                    sc = (obj.apertureRadius)*2 / max(modulation.size);
                    m = stage.core.Mask.createCircularAperture(sc);
                    modulation.setMask(m);
                end
            end
            modulation.color = obj.modulationContrast*obj.bkgValues.*obj.backgroundMeans + obj.backgroundMeans;
            
            p.addStimulus(modulation);
            
            
            % Control when the spot is visible.
            modulationVisible = stage.builtin.controllers.PropertyController(modulation, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.modulationDuration) * 1e-3);
            p.addController(modulationVisible);
            
            % Control the spot color.
            colorController = stage.builtin.controllers.PropertyController(modulation, 'color', ...
                @(state)getModContrast(obj, state.frame, round(obj.frameRate/obj.modulationFrequency)));
            p.addController(colorController);
            end
            
            function c = getModContrast(obj, frame, cycleLength)
                c = (obj.modulationContrast*(2*mod(floor(frame/cycleLength*2),2)-1))...
                    *obj.bkgValues.*obj.backgroundMeans + obj.backgroundMeans;
            end
            
            % Add the test spot.
            if strcmp(obj.flash2Class, 'spot')
                spot = stage.builtin.stimuli.Ellipse();
                spot.radiusX = obj.radius;
                spot.radiusY = obj.radius; 
                spot.position = obj.canvasSize/2;
            else
                spot = stage.builtin.stimuli.Rectangle();
                spot.position = obj.canvasSize/2;
                spot.orientation = 0;
                spot.size = max(obj.canvasSize) * ones(1,2);
                if strcmp(obj.flash2Class, 'annulus')
                    sc = (obj.apertureRadius)*2 / max(spot.size);
                    m = stage.core.Mask.createCircularAperture(sc);
                    spot.setMask(m);
                end
            end 
            if strcmp(obj.chromaticClass,'achromatic') && strcmp(obj.backgroundChromaticClass,'achromatic')
                spot.color = obj.flash2Contrast + obj.rgbMeans;
            else
                spot.color = obj.flash2Contrast*obj.rgbValues.*obj.rgbMeans + obj.rgbMeans;
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= (obj.preTime + obj.modulationDuration + obj.ipi) * 1e-3 && state.time < (obj.preTime + obj.modulationDuration + obj.ipi + obj.flash2Duration) * 1e-3);
            p.addController(spotVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current first flash contrast.
            obj.modulationContrast = obj.modulationContrasts(mod(obj.numEpochsCompleted, length(obj.modulationContrasts))+1);
            % Get the current test flash contrast.
            obj.flash2Contrast = obj.flash2Contrasts(mod(floor(obj.numEpochsCompleted/length(obj.modulationContrasts)), length(obj.flash2Contrasts))+1);
            % Get the current inter-pulse interval.
            obj.ipi = obj.ipis(mod(floor(obj.numEpochsCompleted/length(obj.modulationContrasts)), length(obj.ipis))+1);
            
            % Save the Epoch-specific parameters.
            epoch.addParameter('modulationContrast', obj.modulationContrast);
            epoch.addParameter('flash1Contrast', obj.modulationContrast);
            epoch.addParameter('flash2Contrast', obj.flash2Contrast);
            epoch.addParameter('ipi',obj.ipi);
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.modulationDuration + max(obj.ipis) + obj.flash2Duration;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
    end
end