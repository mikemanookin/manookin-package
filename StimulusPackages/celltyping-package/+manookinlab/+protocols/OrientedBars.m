classdef OrientedBars < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Bar leading duration (ms)
        stimTime = 500                  % Bar duration (ms)
        tailTime = 500                  % Bar trailing duration (ms)
        barSize = [100 1000]            % Bar size (x,y) in microns
        intensity = 1.0                 % Max light intensity (0-1)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        numberOfOrientations = 6        % Number of evenly spaced orientations
        randomOrder = true              % Random sequence of orientations?
        temporalClass = 'pulse'         % Squarewave or pulse?
        chromaticClass = 'achromatic'   % Chromatic class
        onlineAnalysis = 'extracellular'
        numberOfAverages = uint16(18)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'squarewave', 'pulse'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic', 'red', 'green', 'blue', 'yellow', 'L-iso', 'M-iso', 'S-iso', 'LM-iso'})
        orientations
        orientation
        bkg
        barSizePix
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
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            colors = pmkmp(obj.numberOfOrientations,'CubicYF');
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'sweepColor',colors,...
                'groupBy',{'orientation'});
            
            
            obj.barSizePix = obj.rig.getDevice('Stage').um2pix(obj.barSize);
            
            % Create the matrix of bar positions.
            numReps = ceil(double(obj.numberOfAverages) / obj.numberOfOrientations);
            
            % Get the angle increment.
            inc = 180 / obj.numberOfOrientations;
            
            obj.orientations = zeros(obj.numberOfOrientations, numReps);
            for k = 1 : numReps
                if obj.randomOrder
                    obj.orientations(:,k) = (randperm(obj.numberOfOrientations)-1)*inc;
                else
                    obj.orientations(:,k) = (0 : obj.numberOfOrientations-1)*inc;
                end
            end
            obj.orientations = obj.orientations(:)';
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.OrientationFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                    'orientations', unique(obj.orientations));
            end
            
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
            rect.size = obj.barSizePix;
            rect.orientation = obj.orientation;
            rect.position = obj.canvasSize/2;
            
            if strcmp(obj.stageClass, 'Video')
                rect.color = obj.intensity*obj.colorWeights*obj.bkg + obj.bkg;
            else
                rect.color = obj.intensity*obj.bkg + obj.bkg;
            end
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect);       
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            % Control the bar intensity.
            if strcmp(obj.temporalClass, 'squarewave')
                colorController = stage.builtin.controllers.PropertyController(rect, 'color', ...
                    @(state)getSpotColorVideoSqwv(obj, state.time - obj.preTime * 1e-3));
                p.addController(colorController);
            end
            
            function c = getSpotColorVideoSqwv(obj, time)       
                if strcmp(obj.stageClass, 'Video')
                    c = obj.intensity * sign(sin(obj.temporalFrequency*time*2*pi)) * obj.colorWeights * obj.bkg + obj.bkg;
                else
                    c = obj.intensity * sign(sin(obj.temporalFrequncy*time*2*pi)) * obj.bkg + obj.bkg;
                end
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.orientation = obj.orientations(obj.numEpochsCompleted+1);
            epoch.addParameter('orientation', obj.orientation);
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end