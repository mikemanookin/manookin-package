classdef ContrastResponseFigure < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device
        recordingType
        preTime
        stimTime
        contrasts
        groupBy
        groupByValues
        temporalClass
        temporalFrequency
    end
    
    properties (Access = private)
        axesHandle
        yaxis
        repsPerX
    end
    
    methods
        
        function obj = ContrastResponseFigure(device, varargin)
            ip = inputParser();
            ip.addParameter('recordingType', 'extracellular', @(x)ischar(x));
            ip.addParameter('preTime',0.0, @(x)isfloat(x));
            ip.addParameter('stimTime',0.0, @(x)isfloat(x));
            ip.addParameter('contrasts',0.0, @(x)isfloat(x));
            ip.addParameter('groupBy','',@(x)ischar(x));
            ip.addParameter('groupByValues',{},@(x)iscellstr(x));
            ip.addParameter('temporalClass','pulse',@(x)ischar(x));
            ip.addParameter('temporalFrequency',4.0,@(x)isfloat(x));
            
            ip.parse(varargin{:});
            
            obj.device = device;
            obj.recordingType = ip.Results.recordingType;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            obj.contrasts = ip.Results.contrasts;
            obj.groupBy = ip.Results.groupBy;
            obj.groupByValues = ip.Results.groupByValues;
            obj.temporalClass = ip.Results.temporalClass;
            obj.temporalFrequency = ip.Results.temporalFrequency;
            
            % Take only the unique contrasts.
            obj.contrasts = unique(obj.contrasts);
            
            if isempty(obj.groupBy)
                obj.yaxis = zeros(length(obj.contrasts),1);
                obj.repsPerX = zeros(length(obj.contrasts),1);
            else
                obj.yaxis = zeros(length(obj.contrasts),length(obj.groupByValues));
                obj.repsPerX = zeros(length(obj.contrasts),length(obj.groupByValues));
            end
            
            obj.createUi();
        end
        
        function createUi(obj)
            import appbox.*;
            
            obj.axesHandle = axes( ...
                'Parent', obj.figureHandle, ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle, 'contrast');
            ylabel(obj.axesHandle, 'response');
            
            obj.setTitle([obj.device.name ': contrast-response']);
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t); 
        end
        
        function clear(obj)
            cla(obj.axesHandle);
            obj.yaxis = 0*obj.yaxis;
            obj.repsPerX = 0*obj.repsPerX;
        end
        
        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                error(['Epoch does not contain a response for ' obj.device.name]);
            end
            
            response = epoch.getResponse(obj.device);
            [quantities, ~] = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            
            % Define an anonymous function to convert time to points.
            timeToPts = @(t)(t*1e-3*sampleRate);
            
            xval = epoch.parameters('contrast');
            xIndex = obj.contrasts == xval;
            
            % Get the groupBy value for this Epoch.
            if ~isempty(obj.groupBy)
                gbValue = epoch.parameters(obj.groupBy);
                [tf,gbIndex] = ismember(gbValue,obj.groupByValues);
                if ~tf
                    gbIndex = 1;
                end
            else
                gbIndex = 1;
            end
            
            % Get your sample regions.
            prePts = timeToPts(obj.preTime);
            sample = [1 timeToPts(obj.stimTime)] + prePts;
            
            if numel(quantities) > 0
                % Parse the response by type.
                y = responseByType(quantities, obj.recordingType, obj.preTime, sampleRate);
                
                if prePts > 200
                    if strcmp(obj.recordingType, 'extracellular')
                        y = y - mean(y(1 : prePts-200));
                    else
                        y = y - median(y(1 : prePts-200));
                    end
                end
                
                if strcmp(obj.temporalClass, 'pulse')
                    r = mean(y(sample(1) : sample(2)));
                else
                    y = y(sample(1) : sample(2));
                    numCycles = obj.stimTime*1e-3 * obj.temporalFrequency;
                    cyclePts = length(y) / numCycles;
                    avgCycle = zeros(1,floor(cyclePts));
                    for k = 1 : floor(numCycles)
                        ind = round((k-1)*cyclePts) + (1 : floor(cyclePts));
                        avgCycle = avgCycle + y(ind);
                    end
                    avgCycle = avgCycle / k;
                    ft = fft(avgCycle);
                    r = abs(ft(2))/length(ft)*2;
                end
                
                % Iterate the reps.
                obj.repsPerX(xIndex,gbIndex) = obj.repsPerX(xIndex,gbIndex) + 1;
                obj.yaxis(xIndex,gbIndex) = (obj.yaxis(xIndex,gbIndex)*(obj.repsPerX(xIndex,gbIndex)-1) + r)/obj.repsPerX(xIndex,gbIndex);
            end
            
            axColors = {'k','m','b','g'};
            
            % Plot the data.
            cla(obj.axesHandle);
            
            if isempty(obj.groupBy)
                line(obj.contrasts, obj.yaxis,...
                    'Parent', obj.axesHandle, 'Color', 'k', 'Marker', 'o', 'LineStyle', '-');
            else
                for k = 1 : size(obj.yaxis,2)
                    line(obj.contrasts, obj.yaxis(:,k),...
                        'Parent', obj.axesHandle, 'Color', axColors{k}, 'Marker', 'o', 'LineStyle', '-');
                end
                legend(obj.axesHandle,obj.groupByValues,'Location','NorthWest');
            end
            
            set(obj.axesHandle, 'XLim', [min([obj.contrasts(:)',0]) max([obj.contrasts(:)',0])]);
        end
    end
end