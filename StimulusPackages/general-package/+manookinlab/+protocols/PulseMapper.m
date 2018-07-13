classdef PulseMapper < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Bar leading duration (ms)
        stimTime = 500                  % Bar duration (ms)
        tailTime = 750                  % Bar trailing duration (ms)
        stixelSize = 32                 % Stixel size (pixels)
        numStixels = 12                 % Number of stixels
        contrast = 1.0                  % Contrast
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        onlineAnalysis = 'extracellular'         % Online analysis type.
        numberOfAverages = uint16(288)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        intensities
        positions
        intensity
        position
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            obj.organizeParameters();
        end
        
        function organizeParameters(obj)
            v = ((0:obj.numStixels-1)*obj.stixelSize) - (obj.numStixels*obj.stixelSize)/2+obj.stixelSize/2;
            % Set your X/Y positions for the bar.
            obj.positions = zeros(obj.numStixels*2,2);
            count = 0;
            for k = 1 : obj.numStixels
                for m = 1 : obj.numStixels
                    count = count + 1;
                    obj.positions(count,:) = [v(k) v(m)];
                end
            end
            % Randomize the order.
            obj.positions = obj.positions(randperm(count),:);
            
            % Replicate the positions so you can switch contrasts.
            if obj.backgroundIntensity > 0
                tmp = zeros(size(obj.positions,1)*2,2);
                for k = 1 : size(obj.positions,1)
                    index = (k-1)*2 + (1:2);
                    for m = 1 : 2
                        tmp(index(m),:) = obj.positions(k,:);
                    end
                end
                obj.positions = tmp;
                obj.intensities = [obj.contrast -obj.contrast]*obj.backgroundIntensity + obj.backgroundIntensity;
            else
                obj.intensities = obj.contrast*ones(1,2);
            end
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.stixelSize*ones(1,2);
            rect.position = obj.canvasSize/2 + obj.centerOffset + obj.position;
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
            
            obj.position = obj.positions(mod(obj.numEpochsCompleted,length(obj.positions))+1);
            obj.intensity = obj.intensities(mod(obj.numEpochsCompleted,2)+1);
            
            epoch.addParameter('position', obj.position);
            epoch.addParameter('intensity', obj.intensity);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end