classdef OrientedBarGrid < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Bar leading duration (ms)
        stimTime = 500                  % Bar duration (ms)
        tailTime = 500                  % Bar trailing duration (ms)
        barSize = [100 3000]            % Bar size (x,y) in microns
        contrasts = [-1,1.0]            % Max light intensity (0-1)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        numberOfOrientations = 6        % Number of evenly spaced orientations
        randomOrder = true              % Random sequence of orientations?
        onlineAnalysis = 'none'
        numberOfAverages = uint16(468)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        contrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        orientations
        positions
        position
        orientation
        contrast
        contrastMat
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

            obj.barSizePix = obj.rig.getDevice('Stage').um2pix(obj.barSize);
            
            % Get the angle increment.
            inc = 180 / obj.numberOfOrientations;
            
            % Get the position increment
            x_inc = obj.barSizePix(1)/2;
            num_positions_per_orientation = ceil(min(obj.canvasSize)/x_inc)-1;
            x_max = num_positions_per_orientation*x_inc/2 - x_inc/2;
            
            % Get the orientations.
            obj.orientations = repmat((0 : obj.numberOfOrientations-1)*inc,[num_positions_per_orientation,1]);
            % Positions
            obj.positions = repmat(linspace(-x_max,x_max,num_positions_per_orientation)',...
                [1,obj.numberOfOrientations]);
            obj.orientations = obj.orientations(:);
            obj.contrastMat = ones(length(obj.orientations),1) * obj.contrasts(:)';
            obj.contrastMat = obj.contrastMat(:);
            
            % Replicate to show each contrast at each location.
            obj.orientations = repmat(obj.orientations,[length(obj.contrasts),1]);
            obj.positions = repmat(obj.positions(:),[length(obj.contrasts),1]);
            
            % Adjust the position for the bar orientation.
            obj.positions = [cosd(obj.orientations) .* obj.positions(:), ...
                sind(obj.orientations) .* obj.positions(:)];
            
            if obj.randomOrder
                idx = randperm(length(obj.orientations));
                obj.orientations = obj.orientations(idx);
                obj.positions = obj.positions(idx,:);
                obj.contrastMat = obj.contrastMat(idx);
            end
            
            disp([num2str(length(obj.orientations)), ' reps needed to cover the grid!']);
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.OrientationFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                    'orientations', unique(obj.orientations));
            end
            
            obj.bkg = obj.backgroundIntensity;
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.barSizePix;
            rect.orientation = obj.orientation;
            rect.position = obj.position;
            rect.color = obj.contrast*obj.bkg + obj.bkg;
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect);       
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            idx = mod(obj.numEpochsCompleted,length(obj.orientations))+1;
            
            obj.orientation = obj.orientations(idx);
            obj.position = obj.positions(idx,:) + obj.canvasSize/2;
            obj.contrast = obj.contrastMat(idx);
            epoch.addParameter('orientation', obj.orientation);
            epoch.addParameter('position',obj.position);
            epoch.addParameter('contrast',obj.contrast);
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end