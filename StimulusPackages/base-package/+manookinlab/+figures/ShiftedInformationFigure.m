classdef ShiftedInformationFigure < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device
        recordingType
        preTime
        stimTime
        frameRate
        frameDwell
        numFrames
        groupBy
        groupByValues
    end
    
    properties (Access = private)
        axesHandle
        lineHandle
        xaxis
        yaxis
        epochCount
        S
        R
        gbVals
        windowHalfWidth = 30
    end
    
    methods
        
        function obj = ShiftedInformationFigure(device, varargin)
            ip = inputParser();
            ip.addParameter('recordingType', 'extracellular', @(x)ischar(x));
            ip.addParameter('preTime',0.0, @(x)isfloat(x));
            ip.addParameter('stimTime',0.0, @(x)isfloat(x));
            ip.addParameter('frameRate',60.0, @(x)isfloat(x));
            ip.addParameter('groupBy','',@(x)ischar(x));
            ip.addParameter('groupByValues',{},@(x)iscellstr(x));
            ip.addParameter('frameDwell',1,@(x)isfloat(x));
            
            ip.parse(varargin{:});
            
            obj.device = device;
            obj.recordingType = ip.Results.recordingType;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            obj.frameRate = ip.Results.frameRate;
            obj.groupBy = ip.Results.groupBy;
            obj.groupByValues = ip.Results.groupByValues;
            obj.frameDwell = ip.Results.frameDwell;
            
            obj.epochCount = 0;
            
            obj.createUi();
        end
        
        function createUi(obj)
            import appbox.*;
            
            obj.axesHandle = axes( ...
                'Parent', obj.figureHandle, ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle, 'sec');
            
            obj.epochCount = 0;
            obj.R = [];
            obj.S = [];
            obj.gbVals = {};
            
            if isempty(obj.groupBy)
                obj.xaxis = zeros(1,obj.windowHalfWidth*2+1);
                obj.yaxis = zeros(1,obj.windowHalfWidth*2+1);
            else
                obj.xaxis = zeros(length(obj.groupByValues),obj.windowHalfWidth*2+1);
                obj.yaxis = zeros(length(obj.groupByValues),obj.windowHalfWidth*2+1);
            end
            
            obj.setTitle([obj.device.name ': mutual information']);
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t); 
        end
        
        function clear(obj)
            cla(obj.axesHandle);
            % Set the x/y axes
            obj.xaxis = 0*obj.xaxis;
            obj.yaxis = 0*obj.yaxis;
            obj.R = [];
            obj.S = [];
            obj.gbVals = {};
            obj.epochCount = 0;
        end
        
        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                error(['Epoch does not contain a response for ' obj.device.name]);
            end
            
            obj.epochCount = obj.epochCount + 1;
            
            response = epoch.getResponse(obj.device);
            [quantities, ~] = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            prePts = obj.preTime*1e-3*sampleRate;
            stimPts = obj.stimTime*1e-3*sampleRate;
            
            binRate = 60/obj.frameDwell;
            % Account for early frame presentation.
            prePts = prePts - round(sampleRate/obj.frameRate);
            
            if numel(quantities) > 0
                % Parse the response by type.
                y = manookinlab.util.responseByType(quantities, obj.recordingType, obj.preTime, sampleRate);
                
                if strcmp(obj.recordingType,'extracellular') || strcmp(obj.recordingType, 'spikes_CClamp')
                    if sampleRate > binRate
                        y = manookinlab.util.binSpikeCount(y(prePts+(1:stimPts))/sampleRate, binRate, sampleRate);
                    else
                        y = y(prePts+(1:stimPts));
                    end
                else
                    % High-pass filter to get rid of drift.
                    y = highPassFilter(y, 0.2, 1/sampleRate);
                    if prePts > 0
                        y = y - median(y(1:prePts));
                    else
                        y = y - median(y);
                    end
                    y = manookinlab.util.binData(y(prePts+(1:stimPts)), binRate, sampleRate);
                end
                
                % Make sure it's a row.
                y = y(:)';

                % Pull the correlation sequence.
                frameValues = epoch.parameters('correlationSequence');  
                frameValues = frameValues(1 : length(y));

                obj.R(obj.epochCount,:) = y(:)';
                obj.S(obj.epochCount,:) = frameValues(:)';
                
                % Get the groupBy value for this Epoch.
                if ~isempty(obj.groupBy)
                    gbValue = epoch.parameters(obj.groupBy);
                    [tf,gbIndex] = ismember(gbValue,obj.groupByValues);
                    if ~tf
                        gbIndex = 1;
                    end
                    obj.gbVals = [obj.gbVals, gbValue];
                    epochIndex = strcmp(obj.gbVals, gbValue);
                else
                    gbIndex = 1;
                    epochIndex = 1 : obj.epochCount;
                end
                
                % Wait to accumulate enough data before running through the
                % calculations
                if obj.epochCount > 14
                    binWidth = 1e3/obj.frameRate;
                    numStates = 10;
                    [information, t] = manookinlab.util.timeShiftedMutualInfo(obj.S(epochIndex,:), obj.R(epochIndex,:), binWidth, obj.windowHalfWidth, numStates);
                    obj.xaxis(gbIndex,:) = t;
                    obj.yaxis(gbIndex,:) = information;
                    
                    % Plot the data.
                    cla(obj.axesHandle);

                    if ~isempty(obj.groupBy)
                        axColors = [0 0 0; 0.8 0 0; 0 0.5 0; 0 0 1; 0.5 0 0.5; 0 0.5 1; 1 0.5 0];
                        for k = 1 : size(obj.yaxis,1)
                            line(obj.xaxis(k,:), obj.yaxis(k,:),...
                                'Parent', obj.axesHandle, 'Color', axColors(k,:), 'LineStyle', '-');
                        end
                        legend(obj.axesHandle,obj.groupByValues,'Location','NorthEast');
                    end

                    axis(obj.axesHandle, 'tight');
                    title(obj.axesHandle, ['Max/min output: ', num2str(max(abs(obj.yaxis(:))))]);
                end
            end
        end
        
    end
end