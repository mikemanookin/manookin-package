classdef ManookinLabStageProtocol < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    
    properties
        interpulseInterval = 0.5          % Duration between pulses (s)
    end
    
    properties (Hidden)
        stageClass
        frameRate
        canvasSize
        colorWeights
        quantalCatch
        ndf
        objectiveMag
        muPerPixel
        greenLEDName
        labName
    end
    
    methods
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            frameMonitor = obj.rig.getDevices('Frame Monitor');
            if ~isempty(frameMonitor)
                obj.showFigure('edu.washington.riekelab.figures.FrameTimingFigure', obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            end
            
            % Show the progress bar.
            obj.showFigure('manookinlab.figures.ProgressFigure', obj.numberOfAverages);
            
            % Get the frame rate. Need to check if it's a LCR rig.
            if ~isempty(strfind(obj.rig.getDevice('Stage').name, 'LightCrafter'))
                obj.frameRate = obj.rig.getDevice('Stage').getPatternRate();
                obj.stageClass = 'LightCrafter';
            elseif ~isempty(strfind(obj.rig.getDevice('Stage').name, 'LcrRGB'))
                obj.frameRate = obj.rig.getDevice('Stage').getMonitorRefreshRate();
                obj.stageClass = 'LcrRGB';
            else
                obj.frameRate = obj.rig.getDevice('Stage').getMonitorRefreshRate();
                obj.stageClass = 'Video';
            end
            
            rigDev = obj.rig.getDevices('rigProperty');
            if ~isempty(rigDev)
                obj.labName = rigDev{1}.getConfigurationSetting('laboratory');
            else
                obj.labName = 'RiekeLab';
            end
            
            stageRes = obj.rig.getDevice('Stage').getResourceNames();
            
%             d = obj.rig.getDevices();
%             r = d{7}.getResource('quantalCatch');
%             r('10xND00')
%             obj.rig.getDevice('Stage').name
            
            % Look for a filter wheel device.
            fw = obj.rig.getDevices('FilterWheel');
            if ismember('quantalCatch', stageRes)
                obj.quantalCatch = obj.rig.getDevice('Stage').getResource('quantalCatch');
            elseif ~isempty(fw) && strcmp(obj.labName, 'ManookinLab')
                % Get the quantal catch.
                q = load('QCatch.mat');
                
                filterWheel = fw{1};% Get the microscope objective magnification.
                obj.objectiveMag = filterWheel.getObjective();
                
                % Get the NDF wheel setting.
                obj.ndf = filterWheel.getNDF();
                ndString = num2str(obj.ndf * 10);
                if length(ndString) == 1
                    ndString = ['0', ndString];
                end
                obj.greenLEDName = filterWheel.getGreenLEDName();
                if strcmp(obj.greenLEDName, 'Green_505nm')
                    obj.quantalCatch = q.qCatch.(['ndf', ndString])([1 2 4],:);
                else
                    obj.quantalCatch = q.qCatch.(['ndf', ndString])([1 3 4],:);
                end
                obj.muPerPixel = filterWheel.getMicronsPerPixel();
                
                % Adjust the quantal catch depending on the objective.
                if obj.objectiveMag == 4
                    obj.quantalCatch = obj.quantalCatch .* ([0.498627;0.4921139;0.453983]*ones(1,4));
                elseif obj.objectiveMag == 60
                    obj.quantalCatch = obj.quantalCatch .* ([0.664836;0.630064;0.732858]*ones(1,4));
                end
            else
                obj.objectiveMag = 'null';
                obj.ndf = 0;
                obj.quantalCatch = [
                   0.085339321892876   0.049257766442639   0.012802386483357   0.030261353423080
                   0.256255343995659   0.242446609484392   0.020355688054126   0.166042086525636
                   0.078179137266082   0.099240718319820   0.041298793557274   0.115078981568732];
                obj.muPerPixel = 0.8;
                obj.greenLEDName = 'null';
            end
            
            % Get the canvas size.
            obj.canvasSize = obj.rig.getDevice('Stage').getCanvasSize();  
        end
        
        % Set LED weights based on grating type.
        function setColorWeights(obj)
            switch obj.chromaticClass
                case 'red'
                    obj.colorWeights = [1 -1 -1];
                case 'green'
                    obj.colorWeights = [-1 1 -1];
                case 'blue'
                    obj.colorWeights = [-1 -1 1];
                case 'yellow'
                    obj.colorWeights = [1 1 -1];
                case 'L-iso'
                    obj.colorWeights = obj.quantalCatch(:,1:3)' \ [1 0 0]';
                    obj.colorWeights = obj.colorWeights/max(abs(obj.colorWeights));
                case 'M-iso'
                    obj.colorWeights = obj.quantalCatch(:,1:3)' \ [0 1 0]';
                    obj.colorWeights = obj.colorWeights/max(abs(obj.colorWeights));
                case 'S-iso'
                    obj.colorWeights = obj.quantalCatch(:,1:3)' \ [0 0 1]';
                    obj.colorWeights = obj.colorWeights/max(abs(obj.colorWeights));
                case 'LM-iso'
                    obj.colorWeights = obj.quantalCatch(:,1:3)' \ [1 1 0]';
                    obj.colorWeights = obj.colorWeights/max(abs(obj.colorWeights));
                otherwise
                    obj.colorWeights = [1 1 1];
            end
            
            obj.colorWeights = obj.colorWeights(:)';
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            
            if obj.numEpochsCompleted == 0 && ~isempty(obj.persistor)
                % Get the EpochBlock persistor and save the quantal catch
                % values.
                eb = obj.persistor.currentEpochBlock;
                if ~isempty(eb)
                    eb.setProperty('stageClass', obj.stageClass);
                    eb.setProperty('ndf', obj.ndf);
                    if obj.muPerPixel > 0
                        eb.setProperty('micronsPerPixel', obj.muPerPixel);
                        eb.setProperty('objectiveMag', obj.objectiveMag);
                    end
%                     eb.setProperty('maxLCone', sum(obj.quantalCatch(:,1)));
%                     eb.setProperty('maxMCone', sum(obj.quantalCatch(:,2)));
%                     eb.setProperty('maxSCone', sum(obj.quantalCatch(:,3)));
%                     eb.setProperty('maxRod', sum(obj.quantalCatch(:,4)));
                    
                    % Check if this is an MEA rig.
%                     mea = obj.rig.getDevices('MEA');
%                     if ~isempty(mea)
%                         mea = mea{1};
%                         % Try to pull the output file name from the server.
%                         fname = mea.getFileName(30);
%                         if ~isempty(fname)
%                             eb.setProperty('dataFileName', char(fname))
%                         end
%                     end
                end
            end
            
            epoch.addParameter('frameRate', obj.frameRate);
            
            % Check for 2P scanning devices.
            if strcmp(obj.labName, 'ManookinLab')
                obj.checkImaging(epoch);
            end
            
            %--------------------------------------------------------------
            % Set up the amplifiers for recording.
            duration = (obj.preTime + obj.stimTime + obj.tailTime) * 1e-3;
            
            % Get the amplfiers.
            mcDevices = obj.rig.getDevices('Amp');
            
            % Add each amplifier
            for k = 1 : length(mcDevices)
                device = obj.rig.getDevice(mcDevices{k}.name);
                epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
                epoch.addResponse(device);
            end
            
            % Record the frame sync pulses.
            if strcmp(obj.labName, 'ManookinLab')
                if strcmpi(obj.stageClass, 'LightCrafter')
                    frameMonitor = obj.rig.getDevices('White Sync');
                    if ~isempty(frameMonitor)
                        epoch.addResponse(frameMonitor{1});
                    end
                elseif strcmpi(obj.stageClass, 'Video')
                    frameMonitor = obj.rig.getDevices('Red Sync');
                    if ~isempty(frameMonitor)
                        epoch.addResponse(frameMonitor{1});
                    end
                end
            end
        end
        
        function prepareInterval(obj, interval)
            prepareInterval@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, interval);
            
            device = obj.rig.getDevice(obj.amp);
            interval.addDirectCurrentStimulus(device, device.background, obj.interpulseInterval, obj.sampleRate);
        end
        
        function checkImaging(obj, epoch)
            triggers = obj.rig.getDevices('SciScan Trigger');
            if ~isempty(triggers) 
                
                stim = obj.createSciScanTriggerStimulus();
                epoch.addStimulus(triggers{1}, stim);
                
                % Add the devices you need for imaging.
                devNames = {'Green PMT', 'Red PMT', 'SciScan F Clock', 'SciScan S Clock'};
                % Check for the PMT DAQ devices.
                foo = obj.rig.getDevices('Green PMT');
                if ~isempty(foo)
                    for k = 1 : length(devNames)
                        device = obj.rig.getDevice(devNames{k});
                        if ~isempty(device)
                            epoch.addResponse(device);
                        end
                    end
                end
            end
        end
        
        function stim = createSciScanTriggerStimulus(obj)
            gen = symphonyui.builtin.stimuli.PulseGenerator();
            
            gen.preTime = 0;
            gen.stimTime = 10;
            gen.tailTime = obj.preTime + obj.stimTime + obj.tailTime - 10;
            gen.amplitude = 1;
            gen.mean = 0;
            gen.sampleRate = obj.sampleRate;
            gen.units = symphonyui.core.Measurement.UNITLESS;
            
            stim = gen.generate();
        end
        
%         function completeEpoch(obj, epoch)
%             completeEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
%             
%             % Get the frame times and frame rate and append to epoch.
% %             [frameTimes, actualFrameRate] = obj.getFrameTimes(epoch);
% %             epoch.addParameter('frameTimes', frameTimes);
% %             epoch.addParameter('actualFrameRate', actualFrameRate);
%         end
        
        function [frameTimes, actualFrameRate] = getFrameTimes(obj, epoch)
            resp = epoch.getResponse(obj.rig.getDevice('Frame Monitor'));
            frameMonitor = resp.getData();
            
            if sum(frameMonitor) == 0
                frameTimes = [0 0];
                actualFrameRate = 60;
            else
                frameTimes = getFrameTiming(frameMonitor(:)', 1);
                % Take only the frame times during the stimulus.
                frameTimes = frameTimes(frameTimes >= obj.preTime*1e-3*obj.sampleRate & frameTimes <= (obj.preTime+obj.stimTime)*1e-3*obj.sampleRate);
                actualFrameRate = obj.sampleRate / (mean(diff(frameTimes(frameTimes >= obj.preTime/1000*obj.sampleRate))));
            end
        end
        
        function response = getResponseByType(obj, response, onlineAnalysis)
            % Bin the data based on the type.
            %  'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'
            switch onlineAnalysis
                case 'extracellular'
                    response = wavefilter(response(:)', 6);
                    S = spikeDetectorOnline(response);
                    spikesBinary = zeros(size(response));
                    spikesBinary(S.sp) = 1;
                    response = spikesBinary * obj.sampleRate;
                case 'spikes_CClamp'
                    spikeTimes = getThresCross([0 diff(response(:)')], 1.5, 1);
                    spikesBinary = zeros(size(response));
                    spikesBinary(spikeTimes) = 1;
                    response = spikesBinary * obj.sampleRate;
                case 'subthresh_CClamp'
                    spikeTimes = getThresCross([0 diff(response(:)')], 1.5, 1);
                    % Get the subthreshold potential.
                    if ~isempty(spikeTimes)
                        response = getSubthreshold(response(:)', spikeTimes);
                    else
                        response = response(:)';
                    end
                    
                    % Subtract the median.
                    if obj.preTime > 0
                        response = response - median(response(1:round(obj.sampleRate*obj.preTime/1000)));
                    else
                        response = response - median(response);
                    end
                case 'analog'
                    % Deal with band-pass filtering analog data here.
                    response = bandPassFilter(response, 0.2, 500, 1/obj.sampleRate);
                    % Subtract the median.
                    if obj.preTime > 0
                        response = response - median(response(1:round(obj.sampleRate*obj.preTime/1000)));
                    else
                        response = response - median(response);
                    end
            end
        end
        
    end
end