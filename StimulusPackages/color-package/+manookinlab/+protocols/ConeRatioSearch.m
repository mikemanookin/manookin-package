classdef ConeRatioSearch < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 2500                 % Stimulus duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        radius = 200                    % Radius in pixels.
        temporalFrequency = 4.0         % Temporal frequency (Hz)
        stimulusClass = 'full-field'    % Stimulus class
        searchMethod = 'equal catch'    % Search method
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular'         % Online analysis type.
        numberOfAverages = uint16(51)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stimulusClassType = symphonyui.core.PropertyType('char', 'row', {'spot','annulus', 'full-field'})
        searchMethodType = symphonyui.core.PropertyType('char', 'row', {'equal catch', 'gun contrast'})
        backgroundMeans
        ledContrasts
        greenContrasts
        coneContrasts
        lmRatios
        lPlusMContrasts
        lMinusMContrasts
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            % Calculate the background mean values.
            gunMeans = obj.quantalCatch(1:2,1:2)' \ [1; 0.86];
            gunMeans = gunMeans/max(abs(gunMeans));
            obj.backgroundMeans = 0.5*[gunMeans(:)' 0];
            
            % Calculate the parameters for the search.
            switch obj.searchMethod
                case 'equal catch'
                    obj.getEqualCatchParams();
                otherwise
                    obj.getGunContrastParams();
            
            end
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.ContrastResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'preTime',obj.preTime,...
                    'stimTime',obj.stimTime,...
                    'contrasts',unique(obj.lPlusMContrasts),...
                    'temporalClass','drifting',...
                    'temporalFrequency',obj.temporalFrequency);
            end
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundMeans);
            
            if strcmp(obj.stimulusClass, 'spot')
                spot = stage.builtin.stimuli.Ellipse();
                spot.radiusX = obj.radius;
                spot.radiusY = obj.radius; 
                spot.position = obj.canvasSize/2;
            else
                spot = stage.builtin.stimuli.Rectangle();
                spot.size = obj.canvasSize;
                spot.position = obj.canvasSize/2;
                spot.orientation = 0;
            end
            spot.color = obj.backgroundMeans;
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            % Add a center mask if it's an annulus.
            if strcmp(obj.stimulusClass, 'annulus')
                mask = stage.builtin.stimuli.Ellipse();
                mask.radiusX = obj.radius;
                mask.radiusY = obj.radius;
                mask.position = obj.canvasSize/2;
                mask.color = obj.backgroundMeans; 
                p.addStimulus(mask);
            end
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            % Control the spot color.
            colorController = stage.builtin.controllers.PropertyController(spot, 'color', ...
                @(state)getSpotColor(obj, state.time - obj.preTime * 1e-3));
            p.addController(colorController);
            
            function c = getSpotColor(obj, time)
                if time > 0 && time <= obj.stimTime*1e-3
                    c = obj.backgroundMeans .* (obj.ledContrasts*sin(time*obj.temporalFrequency*2*pi)) + obj.backgroundMeans;
                else
                    c = obj.backgroundMeans;
                end
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            if obj.numEpochsCompleted == 0 && ~isempty(obj.persistor)
                % Get the EpochBlock persistor and save the quantal catch
                % values.
                eb = obj.persistor.currentEpochBlock;
                if ~isempty(eb)
                    q = (obj.backgroundMeans(:)*ones(1,4)) .* obj.quantalCatch;
                    eb.setProperty('meanLCone', sum(q(:,1)));
                    eb.setProperty('meanMCone', sum(q(:,2)));
                    eb.setProperty('meanSCone', sum(q(:,3)));
                    eb.setProperty('meanRod', sum(q(:,4)));
                end
            end
            
            % Get the contrast index for this epoch.
            index = mod(obj.numEpochsCompleted,length(obj.greenContrasts))+1;
            
            % Get the led contrasts.
            obj.ledContrasts = [1, obj.greenContrasts(index), 0];
            
            % Save the led contrasts.
            epoch.addParameter('contrast', obj.lPlusMContrasts(index));
            epoch.addParameter('ledContrasts', obj.ledContrasts);
            epoch.addParameter('coneContrast', obj.coneContrasts(index,:));
            epoch.addParameter('lmRatios', obj.lmRatios(index));
            epoch.addParameter('lPlusMContrast',obj.lPlusMContrasts(index));
            epoch.addParameter('lMinusMContrast',obj.lMinusMContrasts(index));
        end
        
        function getGunContrastParams(obj)
            obj.greenContrasts = -0.55:0.02:-0.23; 
            
            ct = zeros(length(obj.greenContrasts),4);
            for k = 1 : length(obj.greenContrasts)
                ct(k,:) = manookinlab.util.coneContrast((obj.backgroundMeans(:)*ones(1,4)).*obj.quantalCatch,[1;obj.greenContrasts(k);0], 'michaelson');
            end
            
            obj.coneContrasts = ct(:,1:3);
            obj.lmRatios = ct(:,1) ./ ct(:,2);
            % Get the L+M contrasts
            obj.lPlusMContrasts = (ct(:,1) + ct(:,2));
            % Get the L-M contrasts.
            obj.lMinusMContrasts = (ct(:,1) - ct(:,2));
        end
        
        function getEqualCatchParams(obj)
            % Define LM ratios to test.
            rv = [
                2.5 -1
                2.25 -1
                2 -1
                1.75 -1
                1.5 -1
                1.25 -1
                1 -1
                1 -1.25
                1 -1.5
                1 -1.75
                1 -2
                1 -2.25
                1 -2.5
                ];
            
            qEqual = (obj.backgroundMeans(1:2)'*ones(1,2)) .* obj.quantalCatch(1:2,1:2);
            ledRatio = zeros(size(rv,1),2);
            ct = zeros(size(rv,1),4);
            for k = 1 : size(rv,1)
                rTmp = qEqual' \ rv(k,:)';
                rTmp = rTmp / max(abs(rTmp));
                ledRatio(k,:) = rTmp;
                ct(k,:) = manookinlab.util.coneContrast((obj.backgroundMeans(:)*ones(1,4)).*obj.quantalCatch,[rTmp;0], 'michaelson');
            end
            obj.greenContrasts = ledRatio(:,2)';
            
            obj.coneContrasts = ct(:,1:3);
            obj.lmRatios = rv(:,1) ./ rv(:,2);
            % Get the L+M contrasts
            obj.lPlusMContrasts = (ct(:,1) + ct(:,2));
            % Get the L-M contrasts.
            obj.lMinusMContrasts = (ct(:,1) - ct(:,2));
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end