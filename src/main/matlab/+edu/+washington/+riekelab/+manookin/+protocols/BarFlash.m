classdef BarFlash < edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 500                   % Spot leading duration (ms)
        stimTime = 500                  % Spot duration (ms)
        tailTime = 500                  % Spot trailing duration (ms)
        intensity = 1.0                 % Bar intensity (0-1)
        barSize = [150 300]             % Bar size [width, height] (pix)
        orientation = 0.0               % Bar orientation in degrees.
        backgroundIntensity = 0.0       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y) 
        chromaticClass = 'achromatic'   % Chromatic class
        onlineAnalysis = 'extracellular'         % Online analysis type.
        numberOfAverages = uint16(6)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic', 'red', 'green', 'blue', 'yellow', 'L-iso', 'M-iso', 'S-iso', 'LM-iso'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        bkg
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.manookin.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.manookin.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',[30 144 255]/255,...
                'groupBy',{'frameRate'});
            
            if strcmp(obj.stageClass, 'LightCrafter')
                obj.chromaticClass = 'achromatic';
            end
            
            if (obj.backgroundIntensity == 0 || strcmp(obj.chromaticClass, 'achromatic'))
                obj.bkg = 0.5;
            else
                obj.bkg = obj.backgroundIntensity;
            end
            
            obj.setColorWeights();
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.barSize;
            rect.orientation = obj.orientation;
            rect.position = obj.canvasSize/2 + obj.centerOffset;
            
            if strcmp(obj.stageClass, 'Video')
                rect.color = obj.intensity*obj.colorWeights*obj.bkg + obj.bkg;
            else
                rect.color = obj.intensity*obj.bkg + obj.bkg;
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect);       
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time > obj.preTime * 1e-3 && state.time <= (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
        end
        
        % Same presentation each epoch in a run. Replay.
        function controllerDidStartHardware(obj)
            controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            if (obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < obj.numberOfAverages)
                obj.rig.getDevice('Stage').replay
            else
                obj.rig.getDevice('Stage').play(obj.createPresentation());
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