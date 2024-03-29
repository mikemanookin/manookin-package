classdef FlashMapper < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 500                  % Stimulus duration (ms)
        tailTime = 500                  % Stimulus trailing duration (ms)
        gridWidth = 300                 % Width of mapping grid (microns)
        stixelSize = 50                 % Stixel edge size (microns)
        contrast = 1.0                  % Contrast (0 - 1)
        chromaticClass = 'achromatic'   % Chromatic type
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Online analysis type.
        numberOfAverages = uint16(144)  % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        chromaticClassType = symphonyui.core.PropertyType('char','row',{'achromatic', 'BY', 'RG'})
        stixelSizePix
        gridWidthPix
        intensity
        stimContrast
        positions
        position
        numChecks
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            obj.gridWidthPix = obj.rig.getDevice('Stage').um2pix(obj.gridWidth);

            % Get the number of checkers
            edgeChecks = ceil(obj.gridWidthPix / obj.stixelSizePix);
            obj.numChecks = edgeChecks^2;
            [x,y] = meshgrid(linspace(-obj.stixelSizePix*edgeChecks/2+obj.stixelSizePix/2,obj.stixelSizePix*edgeChecks/2-obj.stixelSizePix/2,edgeChecks));
            obj.positions = [x(:), y(:)];
            
            % Online analysis figures
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',[0,0,0],...
                    'groupBy',{'frameRate'});
                
                obj.showFigure('manookinlab.figures.FlashMapperFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'preTime',obj.preTime,...
                    'stimTime',obj.stimTime,...
                    'stixelSize',obj.stixelSize,...
                    'gridWidth',obj.gridWidth);
            end
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.stixelSizePix*ones(1,2);
            rect.position = obj.canvasSize/2 + obj.position;
            rect.orientation = 0;
            rect.color = obj.intensity;
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect);
            
            barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(barVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            if mod(obj.numEpochsCompleted,2) == 0
                obj.stimContrast = obj.contrast;
            else
                obj.stimContrast = -obj.contrast;
            end
            
            % Check the chromatic class
            if strcmp(obj.chromaticClass, 'BY') % blue-yellow
                if obj.stimContrast > 0
                    flashColor = 'blue';
                    obj.intensity = [0,0,obj.contrast]*obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    flashColor = 'yellow';
                    obj.intensity = [obj.contrast*ones(1,2),0]*obj.backgroundIntensity + obj.backgroundIntensity;
                end
            elseif strcmp(obj.chromaticClass, 'RG') % red-green
                if obj.stimContrast > 0
                    flashColor = 'red';
                    obj.intensity = [obj.contrast,0,0]*obj.backgroundIntensity + obj.backgroundIntensity;
                else
                    flashColor = 'green';
                    obj.intensity = [0,obj.contrast,0]*obj.backgroundIntensity + obj.backgroundIntensity;
                end
            else
                obj.intensity = obj.stimContrast*obj.backgroundIntensity + obj.backgroundIntensity;
                if obj.stimContrast > 0
                    flashColor = 'white';
                else
                    flashColor = 'black';
                end
            end
            
            obj.position = obj.positions(mod(floor(obj.numEpochsCompleted/2),length(obj.positions))+1,:);
            
            epoch.addParameter('numChecks',obj.numChecks);
            epoch.addParameter('position', obj.position);
            epoch.addParameter('stimContrast', obj.stimContrast);
            epoch.addParameter('flashColor', flashColor);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end
