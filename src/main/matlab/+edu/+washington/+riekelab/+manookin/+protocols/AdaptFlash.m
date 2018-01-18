classdef AdaptFlash < edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Stim leading duration (ms)
        stimTime = 2500                 % Stim duration (ms)
        tailTime = 500                  % Stim trailing duration (ms)
        flash1Contrast = 1.0            % Flash 1 contrast (-1:1)
        flash1Duration = 500            % Flash 1 duration (ms)
        flash2Contrasts = [0.0625 0.0625 0.125 0.25 0.375 0.5 0.75 1] % Test flash contrasts (-1:1)
        flash2Duration = 250            % Test flash duration
        ipis = 25*2.^(0:6)              % Inter-pulse intervals (ms)
        radius = 50                     % Inner radius in pixels.
        apertureRadius = 80             % Blank aperture radius (pix)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        flash1Class = 'spot'            % Stimulus class
        chromaticClass = 'achromatic'   % Chromatic class
        onlineAnalysis = 'extracellular'% Online analysis type.
        numberOfAverages = uint16(24)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        flash1ClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus', 'full-field','center-surround'})
        bkg
        flash2Contrast
        ipi
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
                    'flash1Duration',obj.flash1Duration,...
                    'flash2Duration',obj.flash2Duration,...
                    'flash2Contrasts',obj.flash2Contrasts,...
                    'ipis',obj.ipis);
            end
            
            if obj.backgroundIntensity == 0
                obj.bkg = 0.5;
            else
                obj.bkg = obj.backgroundIntensity;
            end
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            if strcmp(obj.flash1Class, 'spot')
                flash1 = stage.builtin.stimuli.Ellipse();
                flash1.radiusX = obj.radius;
                flash1.radiusY = obj.radius; 
                flash1.position = obj.canvasSize/2 + obj.centerOffset;
            else
                flash1 = stage.builtin.stimuli.Rectangle();
                flash1.position = obj.canvasSize/2 + obj.centerOffset;
                flash1.orientation = 0;
                flash1.size = max(obj.canvasSize) * ones(1,2) + 2*max(abs(obj.centerOffset));
                if strcmp(obj.flash1Class, 'annulus')
                    sc = (obj.apertureRadius)*2 / max(flash1.size);
                    m = stage.core.Mask.createCircularAperture(sc);
                    flash1.setMask(m);
                end
            end
            flash1.color = obj.flash1Contrast * obj.bkg + obj.bkg;
            p.addStimulus(flash1);
            
            % Control when the spot is visible.
            flash1Visible = stage.builtin.controllers.PropertyController(flash1, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.flash1Duration) * 1e-3);
            p.addController(flash1Visible);
            
            % Add the test spot.
            spot = stage.builtin.stimuli.Ellipse();
            spot.radiusX = obj.radius;
            spot.radiusY = obj.radius; 
            spot.position = obj.canvasSize/2 + obj.centerOffset;
            spot.color = obj.flash2Contrast * obj.bkg + obj.bkg;
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= (obj.preTime + obj.flash1Duration + obj.ipi) * 1e-3 && state.time < (obj.preTime + obj.flash1Duration + obj.ipi + obj.flash2Duration) * 1e-3);
            p.addController(spotVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Get the current test flash contrast.
            obj.flash2Contrast = obj.flash2Contrasts(mod(obj.numEpochsCompleted, length(obj.flash2Contrasts))+1);
            % Get the current inter-pulse interval.
            obj.ipi = obj.ipis(mod(obj.numEpochsCompleted, length(obj.ipis))+1);
            
            % Save the Epoch-specific parameters.
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