classdef MeanResponseFigure < symphonyui.core.FigureHandler
    
    properties (SetAccess = private)
        device
        groupBy
        sweepColor
        recordingType
        storedSweepColor
    end
    
    properties (Access = private)
        axesHandle
        sweeps
        sweepIndex
        storedSweep
        legendValues
    end
    
    methods
        
        function obj = MeanResponseFigure(device, varargin)
            co = get(groot, 'defaultAxesColorOrder');

            ip = inputParser();
            ip.addParameter('groupBy', [], @(x)iscellstr(x));
            ip.addParameter('sweepColor', co(1,:), @(x)ischar(x) || ismatrix(x));
            ip.addParameter('storedSweepColor', 'r', @(x)ischar(x) || isvector(x));
            ip.addParameter('recordingType', [], @(x)ischar(x));
            ip.parse(varargin{:});
            
            obj.device = device;
            obj.groupBy = ip.Results.groupBy;
            obj.sweepColor = ip.Results.sweepColor;
            obj.storedSweepColor = ip.Results.storedSweepColor;
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
            obj.sweeps = {};
            obj.legendValues = {};
            obj.setTitle([obj.device.name ' Mean Response']);
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
            title(obj.axesHandle, t);
        end
        
        function clear(obj)
            cla(obj.axesHandle);
            obj.sweeps = {};
            obj.legendValues = {};
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
                
                if strcmp(obj.recordingType, 'extracellular') || strcmp(obj.recordingType, 'spikes_CClamp')
                    y = manookinlab.util.psth(y,6+2/3,sampleRate,1);
                    x = (1:length(y)) / sampleRate;
%                     y = manookinlab.util.binData(y, 60, sampleRate);
%                     x = (1:length(y)) / 60;
                else
                    x = (1:length(y)) / sampleRate;
                end
            else
                x = [];
                y = [];
            end
            
            p = epoch.parameters;
            if isempty(obj.groupBy) && isnumeric(obj.groupBy)
                parameters = p;
            else
                parameters = containers.Map();
                for i = 1:length(obj.groupBy)
                    key = obj.groupBy{i};
                    parameters(key) = p(key);
                end
            end
            
            if isempty(parameters)
                t = 'All epochs grouped together';
            else
                t = ['Grouped by ' strjoin(parameters.keys, ', ')];
            end
            obj.setTitle([obj.device.name ' Mean Response (' t ')']);
            
            obj.sweepIndex = [];
            for i = 1:numel(obj.sweeps)
                if isequal(obj.sweeps{i}.parameters, parameters)
                    obj.sweepIndex = i;
                    break;
                end
            end
            
            if isempty(obj.sweepIndex)
                if size(obj.sweepColor,1) == 1
                    cInd = 1;
                elseif size(obj.sweepColor,1) >= length(obj.sweeps)+1
                    cInd = length(obj.sweeps)+1;
                else
                    cInd = 1;
                    warning('Not enough colors supplied for sweeps')
                end
                sweep.line = line(x, y, 'Parent', obj.axesHandle,...
                    'Color', obj.sweepColor(cInd,:));
                sweep.parameters = parameters;
                sweep.count = 1;
                obj.sweeps{end + 1} = sweep;
                
                % Get the the legend value.
                k = parameters.keys;
                v = parameters(k{1});
                if ~ischar(v)
                    v = num2str(v);
                end
                obj.legendValues{end + 1} = v;
            else
                sweep = obj.sweeps{obj.sweepIndex};
                cy = get(sweep.line, 'YData');
                set(sweep.line, 'YData', (cy * sweep.count + y) / (sweep.count + 1));
                sweep.count = sweep.count + 1;
                obj.sweeps{obj.sweepIndex} = sweep;
            end
            
            %check for stored data to plot...
            storedData = obj.storedAverages();
            if ~isempty(storedData)
                if ~isempty(obj.storedSweep) %Handle still there
                    if obj.storedSweep.line.isvalid %Line still there
                        
                    else
                        obj.storedSweep.line = line(storedData(1,:), storedData(2,:),...
                        'Parent', obj.axesHandle, 'Color', obj.storedSweepColor);
                    end                 
                else %no handle
                    obj.storedSweep.line = line(storedData(1,:), storedData(2,:),...
                        'Parent', obj.axesHandle, 'Color', obj.storedSweepColor);
                end
            end

            ylabel(obj.axesHandle, units, 'Interpreter', 'none');
            if ~isempty(obj.legendValues)
                legend(obj.axesHandle, obj.legendValues);
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
            obj.storedSweep.line = obj.sweeps{sweepPull}.line;
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

