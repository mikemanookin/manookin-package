classdef AutocorrelationFigure < symphonyui.core.FigureHandler
    % Plots the mean response of a specified device for all epochs run.

    properties (SetAccess = private)
        device
        groupBy
        sweepColor
        storedSweepColor
        psth
    end

    properties (Access = private)
        axesHandle
        sweeps
        isi
    end

    methods

        function obj = AutocorrelationFigure(device, varargin)
            co = get(groot, 'defaultAxesColorOrder');

            ip = inputParser();
            ip.addParameter('groupBy', [], @(x)iscellstr(x));
            ip.addParameter('sweepColor', co(1,:), @(x)ischar(x) || ismatrix(x));
            ip.addParameter('storedSweepColor', 'r', @(x)ischar(x) || isvector(x));
            ip.addParameter('psth', false, @(x)islogical(x));
            ip.parse(varargin{:});

            obj.device = device;
            obj.groupBy = ip.Results.groupBy;
            obj.sweepColor = ip.Results.sweepColor;
            obj.storedSweepColor = ip.Results.storedSweepColor;
            obj.psth = ip.Results.psth;

            obj.createUi();

            stored = obj.storedSweeps();
            for i = 1:numel(stored)
                stored{i}.line = line(stored{i}.x, stored{i}.y, ...
                    'Parent', obj.axesHandle, ...
                    'Color', obj.storedSweepColor, ...
                    'HandleVisibility', 'off');
            end
            obj.storedSweeps(stored);
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

            obj.axesHandle = axes( ...
                'Parent', obj.figureHandle, ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle, 'time (msec)');
            obj.sweeps = {};
            obj.isi = [];

            obj.setTitle([obj.device.name ' Autocorrelation']);
        end

        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
            title(obj.axesHandle, t);
        end

        function clear(obj)
            cla(obj.axesHandle);
            obj.sweeps = {};
            obj.isi = [];
        end

        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                error(['Epoch does not contain a response for ' obj.device.name]);
            end

            response = epoch.getResponse(obj.device);
            [quantities, units] = response.getData();
            if numel(quantities) > 0
                sampleRate = response.sampleRate.quantityInBaseUnits;
                
                % Get spike times.
                S = manookinlab.util.spikeDetectorOnline(quantities);
                spikeTimes = S.sp;
                isiTmp = diff(spikeTimes);
                if ~isempty(isiTmp)
                    obj.isi = [obj.isi; isiTmp(:)/sampleRate*1e3];
                    [y,x] = manookinlab.util.getSpikeAutocorrelation(obj.isi);
                    
                    cla(obj.axesHandle);
                    line(x, y, 'Parent', obj.axesHandle, 'Color', [0,0.4470,0.7410],'LineWidth',2);
                end
            end

%             sweep.parameters = [];
%             sweep.x = x;
%             sweep.y = y;
%             sweep.count = 1;
%             sweep.line = line(sweep.x, sweep.y, 'Parent', obj.axesHandle, 'Color', [0,0.4470,0.7410],'LineWidth',2);
%             obj.sweeps{1} = sweep;

            ylabel(obj.axesHandle, 'probability');
        end

    end

    methods (Access = private)

        function onSelectedStoreSweeps(obj, ~, ~)
            obj.storeSweeps();
        end

        function storeSweeps(obj)
            obj.clearSweeps();

            store = obj.sweeps;
            for i = 1:numel(obj.sweeps)
                store{i}.line = copyobj(obj.sweeps{i}.line, obj.axesHandle);
                set(store{i}.line, ...
                    'Color', obj.storedSweepColor, ...
                    'HandleVisibility', 'off');
            end
            obj.storedSweeps(store);
        end

        function onSelectedClearSweeps(obj, ~, ~)
            obj.clearSweeps();
        end

        function clearSweeps(obj)
            stored = obj.storedSweeps();
            for i = 1:numel(stored)
                delete(stored{i}.line);
            end

            obj.storedSweeps([]);
        end

    end

    methods (Static)

        function sweeps = storedSweeps(sweeps)
            % This method stores sweeps across figure handlers.

            persistent stored;
            if nargin > 0
                stored = sweeps;
            end
            sweeps = stored;
        end

    end

end
