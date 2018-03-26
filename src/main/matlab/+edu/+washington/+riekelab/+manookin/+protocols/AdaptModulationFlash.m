classdef AdaptModulationFlash < edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stim leading duration (ms)
        stimTime = 1500                 % Stim duration (ms)
        tailTime = 500                  % Stim trailing duration (ms)
        modulationContrasts = [0 0.8]   % Flash 1 contrast (-1:1)
        modulationDuration = 1250       % Flash 1 duration (ms)
        modulationFrequency = 30.0      % Modulation temporal frequency (Hz)
        flash2Contrasts = [0 0.0625 0.0625 0.125 0.125 0.25 0.25 0.5 0.75 1] % Test flash contrasts (-1:1)
        flash2Duration = 50             % Test flash duration
        ipis = 25*2.^(0:6)              % Inter-pulse intervals (ms)
        radius = 105                    % Inner radius in pixels.
        apertureRadius = 105            % Blank aperture radius (pix)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        modulationClass = 'full-field'  % Adapting flash class
        flash2Class = 'spot'            % Test flash class
        chromaticClass = 'achromatic'   % Chromatic class
        onlineAnalysis = 'extracellular'% Online analysis type.
        numberOfAverages = uint16(60)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','red-green isoluminant','red-green isochromatic'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        modulationClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus', 'full-field'})
        flash2ClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus', 'full-field'})
        bkg
        modulationContrast
        flash2Contrast
        ipi
        rgbMeans
        rgbValues
        backgroundMeans
    end
    
     methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('edu.washington.riekelab.manookin.figures.AdaptFlashFigure', ...
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
            if strcmp(obj.chromaticClass,'achromatic')
                obj.rgbMeans = 0.5;
                obj.rgbValues = 1;
                obj.backgroundMeans = obj.bkg*ones(1,3);
            else
                [obj.rgbMeans, ~, deltaRGB] = getMaxContrast(obj.quantalCatch, obj.chromaticClass);
                obj.rgbValues = deltaRGB*obj.bkg + obj.bkg;
                obj.backgroundMeans = obj.rgbMeans(:)';
            end
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundMeans);
            
            if strcmp(obj.modulationClass, 'spot')
                modulation = stage.builtin.stimuli.Ellipse();
                modulation.radiusX = obj.radius;
                modulation.radiusY = obj.radius; 
                modulation.position = obj.canvasSize/2 + obj.centerOffset;
            else
                modulation = stage.builtin.stimuli.Rectangle();
                modulation.position = obj.canvasSize/2 + obj.centerOffset;
                modulation.orientation = 0;
                modulation.size = max(obj.canvasSize) * ones(1,2) + 2*max(abs(obj.centerOffset));
                if strcmp(obj.modulationClass, 'annulus')
                    sc = (obj.apertureRadius)*2 / max(modulation.size);
                    m = stage.core.Mask.createCircularAperture(sc);
                    modulation.setMask(m);
                end
            end
            modulation.color = obj.modulationContrast*obj.rgbValues.*obj.backgroundMeans + obj.backgroundMeans;
            p.addStimulus(modulation);
            
            % Control when the spot is visible.
            modulationVisible = stage.builtin.controllers.PropertyController(modulation, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.modulationDuration) * 1e-3);
            p.addController(modulationVisible);
            
            % Control the spot color.
            colorController = stage.builtin.controllers.PropertyController(modulation, 'color', ...
                @(state)getModContrast(obj, state.frame, round(obj.frameRate/obj.modulationFrequency)));
            p.addController(colorController);
            
            function c = getModContrast(obj, frame, cycleLength)
                c = (obj.modulationContrast*(2*mod(floor(frame/cycleLength*2),2)-1))...
                    *obj.rgbValues.*obj.backgroundMeans + obj.backgroundMeans;
%                 if time > 0 && time <= obj.stimTime*1e-3
%                     c = (obj.modulationContrast*sign(sin(time*2*pi*obj.modulationFrequency)))...
%                         *obj.rgbValues.*obj.backgroundMeans + obj.backgroundMeans;
%                 else
%                     c = obj.backgroundMeans;
%                 end
            end
            
%             % Control the spot color.
%             colorController = stage.builtin.controllers.PropertyController(modulation, 'color', ...
%                 @(state)getModContrast(obj, state.time - obj.preTime * 1e-3));
%             p.addController(colorController);
%             
%             function c = getModContrast(obj, time)
%                 if time > 0 && time <= obj.stimTime*1e-3
%                     c = (obj.modulationContrast*sign(sin(time*2*pi*obj.modulationFrequency)))...
%                         *obj.rgbValues.*obj.backgroundMeans + obj.backgroundMeans;
%                 else
%                     c = obj.backgroundMeans;
%                 end
%             end
            
            % Add the test spot.
            if strcmp(obj.flash2Class, 'spot')
                spot = stage.builtin.stimuli.Ellipse();
                spot.radiusX = obj.radius;
                spot.radiusY = obj.radius; 
                spot.position = obj.canvasSize/2 + obj.centerOffset;
            else
                spot = stage.builtin.stimuli.Rectangle();
                spot.position = obj.canvasSize/2 + obj.centerOffset;
                spot.orientation = 0;
                spot.size = max(obj.canvasSize) * ones(1,2) + 2*max(abs(obj.centerOffset));
                if strcmp(obj.flash2Class, 'annulus')
                    sc = (obj.apertureRadius)*2 / max(spot.size);
                    m = stage.core.Mask.createCircularAperture(sc);
                    spot.setMask(m);
                end
            end
            spot.color = obj.flash2Contrast*obj.rgbValues.*obj.backgroundMeans + obj.backgroundMeans;
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= (obj.preTime + obj.modulationDuration + obj.ipi) * 1e-3 && state.time < (obj.preTime + obj.modulationDuration + obj.ipi + obj.flash2Duration) * 1e-3);
            p.addController(spotVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current first flash contrast.
            obj.modulationContrast = obj.modulationContrasts(mod(obj.numEpochsCompleted, length(obj.modulationContrasts))+1);
            % Get the current test flash contrast.
            obj.flash2Contrast = obj.flash2Contrasts(mod(floor(obj.numEpochsCompleted/length(obj.modulationContrasts)), length(obj.flash2Contrasts))+1);
            % Get the current inter-pulse interval.
            obj.ipi = obj.ipis(mod(obj.numEpochsCompleted, length(obj.ipis))+1);
            
            % Save the Epoch-specific parameters.
            epoch.addParameter('modulationContrast', obj.modulationContrast);
            epoch.addParameter('flash1Contrast', obj.modulationContrast);
            epoch.addParameter('flash2Contrast', obj.flash2Contrast);
            epoch.addParameter('ipi',obj.ipi);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
    end
end