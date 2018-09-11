classdef sMTFFigure < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device
        xaxis
        recordingType
        temporalType
        spatialType
        xName
        preTime
        stimTime
        temporalFrequency
    end
    
    properties (Access = private)
        axesHandle
        phaseAxesHandle
        yaxis
        yaxis2
        f0
        paxis % Phase data
        repsPerX
        lineHandle
        lineHandle2
        phaseHandle
        fitLine
    end
    
    methods
        function obj = sMTFFigure(device, varargin)
            
            ip = inputParser();
            ip.addParameter('preTime',0.0, @(x)isfloat(x));
            ip.addParameter('stimTime',0.0, @(x)isfloat(x));
            ip.addParameter('recordingType', 'extracellular', @(x)ischar(x));
            ip.addParameter('temporalType', 'pulse', @(x)ischar(x));
            ip.addParameter('spatialType', 'spot', @(x)ischar(x));
            ip.addParameter('xName', 'currentRadius', @(x)ischar(x));
            ip.addParameter('xaxis',[], @(x)isfloat(x));
            ip.addParameter('temporalFrequency',0.0, @(x)isfloat(x));
            ip.parse(varargin{:});

            obj.device = device;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            obj.recordingType = ip.Results.recordingType;
            obj.temporalType = ip.Results.temporalType;
            obj.spatialType = ip.Results.spatialType;
            obj.xName = ip.Results.xName;
            obj.xaxis = ip.Results.xaxis;
            obj.temporalFrequency = ip.Results.temporalFrequency;
            
            % Set up the yaxis and reps
            obj.yaxis = zeros(size(obj.xaxis));
            obj.yaxis2 = zeros(size(obj.xaxis));
            obj.paxis = zeros(size(obj.xaxis));
            obj.f0 = zeros(size(obj.xaxis));
            obj.repsPerX = zeros(size(obj.xaxis));

            obj.createUi();
        end
        
        function createUi(obj)
            import appbox.*;
            
            if strcmpi(obj.temporalType, 'pulse')
                obj.axesHandle = axes( ...
                    'Parent', obj.figureHandle, ...
                    'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                    'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                    'XTickMode', 'auto');
                xlabel(obj.axesHandle, obj.xName);
                ylabel(obj.axesHandle, 'response');
                obj.setTitle('spatial modulation profile');
            else
                obj.axesHandle = subplot(3, 1, 1:2, ...
                    'Parent', obj.figureHandle, ...
                    'FontUnits', get(obj.figureHandle, 'DefaultUicontrolFontUnits'), ...
                    'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                    'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                    'XTickMode', 'auto');  
                ylabel(obj.axesHandle, 'response');
                obj.setTitle('spatial modulation profile');

                obj.phaseAxesHandle = subplot(3, 1, 3, ...
                    'Parent', obj.figureHandle, ...
                    'FontUnits', get(obj.figureHandle, 'DefaultUicontrolFontUnits'), ...
                    'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                    'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                    'XTickMode', 'auto');
                xlabel(obj.phaseAxesHandle, obj.xName);
                ylabel(obj.phaseAxesHandle, 'phase');
            end
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
            title(obj.axesHandle, t);
        end
        
        function clear(obj)
            cla(obj.axesHandle);
            cla(obj.phaseAxesHandle);
            obj.yaxis = zeros(size(obj.xaxis));
            obj.yaxis2 = zeros(size(obj.xaxis));
            obj.f0 = zeros(size(obj.xaxis));
            obj.paxis = zeros(size(obj.xaxis));
            obj.repsPerX = zeros(size(obj.xaxis));
        end
        
        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                error(['Epoch does not contain a response for ' obj.device.name]);
            end
            
            binRate = 60; % Data bin rate in Hz
            response = epoch.getResponse(obj.device);
            [quantities, ~] = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            prePts = obj.preTime*1e-3*sampleRate;
            stimFrames = obj.stimTime*1e-3*binRate;
            xval = epoch.parameters(obj.xName);
            xIndex = obj.xaxis == xval;
            if numel(quantities) > 0
                y = quantities;
                
                if strcmp(obj.recordingType,'extracellular')
                    res = manookinlab.util.spikeDetectorOnline(y,[],sampleRate);
                    y = zeros(size(y));
                    y(res.sp) = 1; %spike binary
                    y = manookinlab.util.BinSpikeRate(y(prePts+1:end), binRate, sampleRate);
                else
                    if prePts > 0
                        y = y - median(y(1:prePts));
                    else
                        y = y - median(y);
                    end
                    y = manookinlab.util.binData(y(prePts+1:end), binRate, sampleRate);
                end
                     
                % Iterate the reps.
                obj.repsPerX(xIndex) = obj.repsPerX(xIndex) + 1;
                % Get the response during the stimulus window.
                if strcmp(obj.temporalType, 'pulse')     
                    obj.yaxis(xIndex) = (obj.yaxis(xIndex)*(obj.repsPerX(xIndex)-1) + mean(y(1 : stimFrames)))/obj.repsPerX(xIndex);
                    obj.yaxis2(xIndex) = (obj.yaxis2(xIndex)*(obj.repsPerX(xIndex)-1) + mean(y(stimFrames+1:end)))/obj.repsPerX(xIndex);
                else % This is temporal modulation
                    tfreq = obj.temporalFrequency;
                    binSize = binRate / tfreq;
                    numBins = floor(stimFrames / binSize);
                    avgCycle = zeros(1,floor(binSize));
                    for k = 1 : numBins
                        index = round((k-1)*binSize)+(1:floor(binSize));
                        index(index > length(y)) = [];
                        ytmp = y(index);
                        avgCycle = avgCycle + ytmp(:)';
                    end
                    avgCycle = avgCycle / numBins;
                    % Take the fft.
                    ft = fft(avgCycle);
                    obj.yaxis(xIndex) = (obj.yaxis(xIndex)*(obj.repsPerX(xIndex)-1) +...
                        abs(ft(2))/length(avgCycle)*2)/obj.repsPerX(xIndex);
                    obj.yaxis2(xIndex) = (obj.yaxis2(xIndex)*(obj.repsPerX(xIndex)-1) +...
                        abs(ft(3))/length(avgCycle)*2)/obj.repsPerX(xIndex);
                    obj.f0(xIndex) = (obj.yaxis(xIndex)*(obj.repsPerX(xIndex)-1) +...
                        abs(ft(1))/length(avgCycle))/obj.repsPerX(xIndex);
                    obj.paxis(xIndex) = (obj.paxis(xIndex)*(obj.repsPerX(xIndex)-1) +...
                        angle(ft(2)))/obj.repsPerX(xIndex);
                end
            end
            
            cla(obj.axesHandle);
            
            % Create your plot.
            obj.lineHandle = line(obj.xaxis, obj.yaxis,...
                'Parent', obj.axesHandle, 'Color', 'k', 'Marker', 'o');
            obj.lineHandle2 = line(obj.xaxis, obj.yaxis2,...
                'Parent', obj.axesHandle, 'Color', 'r', 'Marker', 'o');
            if strcmp(obj.temporalType, 'pulse')
                legend(obj.axesHandle, 'pulse', 'tail', 'Location', 'NorthEast');
            else
                line(obj.xaxis, obj.f0,...
                    'Parent', obj.axesHandle, 'Color', 'g', 'Marker', 'o');
                legend(obj.axesHandle, 'F1', 'F2', 'F0', 'Location', 'NorthEast');
                cla(obj.phaseAxesHandle);
                obj.phaseHandle = line(obj.xaxis, obj.paxis,...
                    'Parent', obj.phaseAxesHandle, 'Color', 'k', 'Marker', 'o');
            end
            
            % Plot the fit after making it through at least one cycle.
            if sum(obj.repsPerX) >= length(obj.repsPerX)
                yd = abs(obj.yaxis(:)');
                params0 = [max(yd) 200 0.1*max(yd) 400];
                if strcmpi(obj.spatialType, 'spot')
                    [Kc,sigmaC,Ks,sigmaS] = manookinlab.util.fitDoGAreaSummation(2*obj.xaxis(:)', yd, params0);
                    res = manookinlab.util.DoGAreaSummation([Kc,sigmaC,Ks,sigmaS], 2*obj.xaxis(:)');
                else
                    params = manookinlab.util.fitAnnulusAreaSum([obj.xaxis(:)' 456], yd, params0);
                    res = manookinlab.util.annulusAreaSummation(params, [obj.xaxis(:)' 456]);
                    sigmaC = params(2);
                    sigmaS  = params(4);
                end
                obj.fitLine = line(obj.xaxis, res, ...
                    'Parent', obj.axesHandle, 'Color', 'm');
                % Display the fitted parameters.
                title(obj.axesHandle, ['center: ',num2str(round(sigmaC)), '; surround: ',num2str(round(sigmaS))]);
            end
            
            set(obj.axesHandle, 'XLim', [0 max(obj.xaxis)]);
            set(obj.phaseAxesHandle, 'XLim', [0 max(obj.xaxis)]);
        end
    end
    
end