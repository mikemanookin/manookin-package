classdef IntegratedResponseFigure < symphonyui.core.FigureHandler
    
    properties (SetAccess = private)
        device
        groupBy
        sweepColor
        recordingType
        storedSweepColor
    end
    
    properties (Access = private)
        axesHandle
        sweepIndex
        xValues
        yValues
        xMean
        yMean
        preTime
        stimTime
    end
    
    methods
        
        function obj = IntegratedResponseFigure(device, varargin)
            co = get(groot, 'defaultAxesColorOrder');

            ip = inputParser();
            ip.addParameter('groupBy', [], @(x)iscellstr(x));
            ip.addParameter('preTime',0.0, @(x)isfloat(x));
            ip.addParameter('stimTime',0.0, @(x)isfloat(x));
            ip.addParameter('recordingType', [], @(x)ischar(x));
            ip.parse(varargin{:});
            
            obj.device = device;
            obj.groupBy = ip.Results.groupBy;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            obj.recordingType = ip.Results.recordingType;
            
            obj.createUi();
        end
        
        function createUi(obj)
            import appbox.*;
            iconDir = [fileparts(fileparts(mfilename('fullpath'))), '\+utils\+icons\'];
            toolbar = findall(obj.figureHandle, 'Type', 'uitoolbar');
            storeSweepButton = uipushtool( ...
                'Parent', toolbar, ...
                'TooltipString', 'Store Sweep', ...
                'Separator', 'on', ...
                'ClickedCallback', @obj.onSelectedStoreSweep);
            setIconImage(storeSweepButton, symphonyui.app.App.getResource('icons/sweep_store.png'));
            
            clearStoredButton = uipushtool( ...
                'Parent', toolbar, ...
                'TooltipString', 'Clear saved sweep', ...
                'Separator', 'off', ...
                'ClickedCallback', @obj.onSelectedClearStored);
            setIconImage(clearStoredButton, [iconDir, 'Xout.png']);
            
            obj.axesHandle = axes( ...
                'Parent', obj.figureHandle, ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle, 'sec');
            obj.yValues = [];
            obj.xValues = [];
            obj.setTitle([obj.device.name ' Integrated Response']);
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
            title(obj.axesHandle, t);
        end
        
        function clear(obj)
            cla(obj.axesHandle);
            obj.yValues = [];
            obj.xValues = [];
        end
        
        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                error(['Epoch does not contain a response for ' obj.device.name]);
            end
            
            response = epoch.getResponse(obj.device);
            [quantities, units] = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            if numel(quantities) > 0
                y = quantities;
                
                y = manookinlab.util.responseByType(y, obj.recordingType, 0, sampleRate);
                
                prePts = round(obj.preTime*1e-3*sampleRate);
                stimPts = round(obj.stimTime*1e-3*sampleRate);
                
                y = sum(y(prePts+(501:stimPts)));
            else
                y = [];
            end
            
            x = epoch.parameters(obj.groupBy{1});
            
            obj.xValues(end + 1) = x;
            obj.yValues(end + 1) = y;
            
            obj.setTitle([obj.device.name ' Integrated Response (' obj.groupBy{1} ')']);
            
            xsort = unique(x);
            ysort = zeros(size(xsort));
            for k = 1 : length(xsort)
                index = (obj.xValues == xsort(k));
                ysort(k) = mean(obj.yValues(index));
            end
            cla(obj.axesHandle);
            line(xsort, ysort,...
                'LineStyle','-','LineWidth',2,...
                'Marker','o','MarkerFaceColor','k',...
                'Parent', obj.axesHandle, 'Color', 'k');
            

            ylabel(obj.axesHandle, units, 'Interpreter', 'none');
            if ~isempty(obj.xValues)
                legend(obj.axesHandle, obj.groupBy{1});
            end
            
        end
        
    end
    
    methods (Access = private)
        
        function onSelectedStoreSweep(obj, ~, ~)
            if isempty(obj.sweepIndex)
                sweepPull = 1;
            else
                sweepPull = obj.sweepIndex;
            end
            if ~isempty(obj.storedSweep) %Handle still there
                if obj.storedSweep.line.isvalid %Line still there
                    %delete the old storedSweep
                    obj.onSelectedClearStored(obj)
                end
            end
            
            %save out stored data
            obj.storedSweep.line = obj.yValues{sweepPull}.line;
            obj.storedAverages([obj.storedSweep.line.XData; obj.storedSweep.line.YData]);
            %set the saved trace to storedSweepColor to indicate that it has been saved
            obj.storedSweep.line = line(obj.storedSweep.line.XData, obj.storedSweep.line.YData,...
                        'Parent', obj.axesHandle, 'Color', obj.storedSweepColor);
        end

        function onSelectedClearStored(obj, ~, ~)
            obj.storedAverages('Clear');
            obj.storedSweep.line.delete
        end

    end
    
    methods (Static)
        
        
        function averages = storedAverages(averages)
            % This method stores means across figure handlers.
            persistent stored;
            if (nargin == 0) %retrieve stored data
               averages = stored;
            else %set or clear stored data
                if strcmp(averages,'Clear')
                    stored = [];
                else
                    stored = averages;
                    averages = stored;
                end
            end
        end
    end
        
end

