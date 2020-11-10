classdef DualMeanResponseFigure < symphonyui.core.FigureHandler
    % Plots the mean response of two specified devices for all epochs run.
    
    properties (SetAccess = private)
        recordingType
        device1
        groupBy1
        sweepColor1
        storedSweepColor1
        
        device2
        groupBy2
        sweepColor2
        storedSweepColor2
    end
    
    properties (Access = private)
        axesHandle1
        sweeps1
        
        axesHandle2
        sweeps2
    end
    
    methods
        
        function obj = DualMeanResponseFigure(device1, device2, varargin)
            co = get(groot, 'defaultAxesColorOrder');
            
            ip = inputParser();
            ip.addParameter('groupBy1', [], @(x)iscellstr(x));
            ip.addParameter('sweepColor1', co(1,:), @(x)ischar(x) || isvector(x));
            ip.addParameter('storedSweepColor1', 'r', @(x)ischar(x) || isvector(x));
            ip.addParameter('groupBy2', [], @(x)iscellstr(x));
            ip.addParameter('sweepColor2', co(2,:), @(x)ischar(x) || isvector(x));
            ip.addParameter('storedSweepColor2', 'r', @(x)ischar(x) || isvector(x));
            ip.addParameter('recordingType', [], @(x)ischar(x));
            ip.parse(varargin{:});
            
            obj.recordingType = ip.Results.recordingType;
            
            obj.device1 = device1;
            obj.groupBy1 = ip.Results.groupBy1;
            obj.sweepColor1 = ip.Results.sweepColor1;
            obj.storedSweepColor1 = ip.Results.storedSweepColor1;
            
            obj.device2 = device2;
            obj.groupBy2 = ip.Results.groupBy2;
            obj.sweepColor2 = ip.Results.sweepColor2;
            obj.storedSweepColor2 = ip.Results.storedSweepColor2;
            
            obj.createUi();
            
            stored1 = obj.storedSweeps1();
            for i = 1:numel(stored1)
                stored1{i}.line = line(stored1{i}.x, stored1{i}.y, ...
                    'Parent', obj.axesHandle1, ...
                    'Color', obj.storedSweepColor1, ...
                    'HandleVisibility', 'off');
            end
            obj.storedSweeps1(stored1);
            
            stored2 = obj.storedSweeps2();
            for i = 1:numel(stored2)
                stored2{i}.line = line(stored2{i}.x, stored2{i}.y, ...
                    'Parent', obj.axesHandle2, ...
                    'Color', obj.storedSweepColor2, ...
                    'HandleVisibility', 'off');
            end
            obj.storedSweeps2(stored2);
        end
        
        function createUi(obj)
            import appbox.*;
            
            toolbar = findall(obj.figureHandle, 'Type', 'uitoolbar');
            storeSweepsButton = uipushtool( ...
                'Parent', toolbar, ...
                'TooltipString', 'Store Sweeps', ...
                'Separator', 'on', ...
                'ClickedCallback', @obj.onSelectedStoreSweeps);
            setIconImage(storeSweepsButton, symphonyui.app.App.getResource('icons', 'sweep_store.png'));
            
            clearSweepsButton = uipushtool( ...
                'Parent', toolbar, ...
                'TooltipString', 'Clear Sweeps', ...
                'ClickedCallback', @obj.onSelectedClearSweeps);
            setIconImage(clearSweepsButton, symphonyui.app.App.getResource('icons', 'sweep_clear.png'));
            
            obj.axesHandle1 = subplot(2, 1, 1, ...
                'Parent', obj.figureHandle, ...
                'FontUnits', get(obj.figureHandle, 'DefaultUicontrolFontUnits'), ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle1, 'sec');
            title(obj.axesHandle1, [obj.device1.name ' Mean Response']);
            obj.sweeps1 = {};
            
            obj.axesHandle2 = subplot(2, 1, 2, ...
                'Parent', obj.figureHandle, ...
                'FontUnits', get(obj.figureHandle, 'DefaultUicontrolFontUnits'), ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle2, 'sec');
            title(obj.axesHandle2, [obj.device2.name ' Mean Response']);
            obj.sweeps2 = {};
            
            set(obj.figureHandle, 'Name', [obj.device1.name ' and ' obj.device2.name ' Mean Response']);
        end
        
        function clear(obj)
            cla(obj.axesHandle1);
            obj.sweeps1 = {};
            
            cla(obj.axesHandle2);
            obj.sweeps2 = {};
        end
        
        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device1) || ~epoch.hasResponse(obj.device2)
                error(['Epoch does not contain a response for ' obj.device1.name ' or ' obj.device2.name]);
            end
            
            obj.sweeps1 = plotResponse(epoch.getResponse(obj.device1), epoch.parameters, obj.groupBy1, obj.device1.name, ...
                obj.axesHandle1, obj.sweeps1, obj.sweepColor1);
            obj.sweeps2 = plotResponse(epoch.getResponse(obj.device2), epoch.parameters, obj.groupBy2, obj.device2.name, ...
                obj.axesHandle2, obj.sweeps2, obj.sweepColor2);
            
            function sweeps = plotResponse(response, epochParameters, groupBy, deviceName, axesHandle, sweeps, sweepColor)
                [quantities, units] = response.getData();
                if numel(quantities) > 0
                    x = (1:numel(quantities)) / response.sampleRate.quantityInBaseUnits;
                    
                    y = manookinlab.util.responseByType(quantities, obj.recordingType, 0, response.sampleRate.quantityInBaseUnits);
                
                    if strcmp(obj.recordingType, 'extracellular') || strcmp(obj.recordingType, 'spikes_CClamp')
                        y = manookinlab.util.psth(y,6+2/3,response.sampleRate.quantityInBaseUnits,1);
                    end
                else
                    x = [];
                    y = [];
                end

                p = epochParameters;
                if isempty(groupBy) && isnumeric(groupBy)
                    parameters = p;
                else
                    parameters = containers.Map();
                    for i = 1:length(groupBy)
                        key = groupBy{i};
                        parameters(key) = p(key);
                    end
                end

                if isempty(parameters)
                    t = 'All epochs grouped together';
                else
                    t = ['Grouped by ' strjoin(parameters.keys, ', ')];
                end
                title(axesHandle, [deviceName ' Mean Response (' t ')']);

                sweepIndex = [];
                for i = 1:numel(sweeps)
                    if isequal(sweeps{i}.parameters, parameters)
                        sweepIndex = i;
                        break;
                    end
                end

                if isempty(sweepIndex)
                    sweep.parameters = parameters;
                    sweep.x = x;
                    sweep.y = y;
                    sweep.count = 1;
                    sweep.line = line(sweep.x, sweep.y, 'Parent', axesHandle, 'Color', sweepColor);
                    sweeps{end + 1} = sweep;
                else
                    sweep = sweeps{sweepIndex};
                    sweep.y = (sweep.y * sweep.count + y) / (sweep.count + 1);
                    sweep.count = sweep.count + 1;
                    set(sweep.line, 'YData', sweep.y);
                    sweeps{sweepIndex} = sweep;
                end

                ylabel(axesHandle, units, 'Interpreter', 'none');
            end
        end
        
    end
    
    methods (Access = private)
        
        function onSelectedStoreSweeps(obj, ~, ~)
            obj.storeSweeps();
        end
        
        function storeSweeps(obj)
            obj.clearSweeps();
            
            store1 = storeSweeps(obj.sweeps1, obj.axesHandle1, obj.storedSweepColor1);
            store2 = storeSweeps(obj.sweeps2, obj.axesHandle2, obj.storedSweepColor2);
            
            function store = storeSweeps(store, axesHandle, storedSweepColor)         
                for k = 1:numel(store)
                    store{k}.line = copyobj(store{k}.line, axesHandle);
                    set(store{k}.line, ...
                        'Color', storedSweepColor, ...
                        'HandleVisibility', 'off');
                end
            end
            
            obj.storedSweeps1(store1);
            obj.storedSweeps2(store2);
        end
        
        function onSelectedClearSweeps(obj, ~, ~)
            obj.clearSweeps();
        end
        
        function clearSweeps(obj)
            stored1 = obj.storedSweeps1();
            for i = 1:numel(stored1)
                delete(stored1{i}.line);
            end
            
            stored2 = obj.storedSweeps2();
            for i = 1:numel(stored2)
                delete(stored2{i}.line);
            end
            
            obj.storedSweeps1([]);
            obj.storedSweeps2([]);
        end
        
    end
    
    methods (Static)

        function sweeps = storedSweeps1(sweeps)
            % This method stores sweeps1 across figure handlers.

            persistent stored;
            if nargin > 0
                stored = sweeps;
            end
            sweeps = stored;
        end
        
        function sweeps = storedSweeps2(sweeps)
            % This method stores sweeps2 across figure handlers.

            persistent stored;
            if nargin > 0
                stored = sweeps;
            end
            sweeps = stored;
        end

    end
        
end

