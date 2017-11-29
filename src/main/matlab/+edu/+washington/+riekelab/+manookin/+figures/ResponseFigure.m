classdef ResponseFigure < symphonyui.core.FigureHandler
    % Plots the response of a specified device in the most recent epoch.

    properties (SetAccess = private)
        devices
        sweepColor
        storedSweepColor
    end

    properties (Access = private)
        axesHandle
        sweep
        storedSweep
    end
    
    properties (Hidden)
        sweepColors = {'k', 'r', 'c', 'm'}
        numEpochsHandled
        numberOfAverages
    end

    methods

        function obj = ResponseFigure(devices, varargin)
            co = get(groot, 'defaultAxesColorOrder');
            
            ip = inputParser();
            ip.addParameter('sweepColor', co(1,:), @(x)ischar(x) || isvector(x));
            ip.addParameter('storedSweepColor', 'r', @(x)ischar(x) || isvector(x));
            ip.addParameter('numberOfAverages', 1, @(x)isinteger(x) || isfloat(x));
            ip.parse(varargin{:});

            obj.devices = devices;
            obj.sweepColor = ip.Results.sweepColor;
            obj.storedSweepColor = ip.Results.storedSweepColor;
            obj.numberOfAverages = ip.Results.numberOfAverages;
            obj.numEpochsHandled = 0;

            obj.createUi();
        end

        function createUi(obj)
            import appbox.*;

            toolbar = findall(obj.figureHandle, 'Type', 'uitoolbar');
            storeSweepButton = uipushtool( ...
                'Parent', toolbar, ...
                'TooltipString', 'Store Sweep', ...
                'Separator', 'on', ...
                'ClickedCallback', @obj.onSelectedStoreSweep);
            setIconImage(storeSweepButton, symphonyui.app.App.getResource('icons', 'sweep_store.png'));

            obj.axesHandle = axes( ...
                'Parent', obj.figureHandle, ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle, 'sec');
            
            % Set the device names.
%             deviceNames = 
            
            obj.setTitle(['completed epoch ',num2str(obj.numEpochsHandled),' of ',num2str(obj.numberOfAverages)]);

%             obj.setTitle([obj.device.name ' Response']);
        end

        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
            title(obj.axesHandle, t);
        end

        function clear(obj)
            cla(obj.axesHandle);
            obj.sweep = [];
            obj.numEpochsHandled = 0;
        end

        function handleEpoch(obj, epoch)
            obj.numEpochsHandled = obj.numEpochsHandled + 1; % Increment the counter
            obj.setTitle(['completed epoch ',num2str(obj.numEpochsHandled),' of ',num2str(obj.numberOfAverages)]);
            for k = 1 : length(obj.devices)
                device = obj.devices{k};
                if ~epoch.hasResponse(device)
                    error(['Epoch does not contain a response for ' device.name]);
                end

                response = epoch.getResponse(device);
                [quantities, units] = response.getData();
                if numel(quantities) > 0
                    x = (1:numel(quantities)) / response.sampleRate.quantityInBaseUnits;
                    y = quantities;
                else
                    x = [];
                    y = [];
                end
                if isempty(obj.sweep) || size(obj.sweep, 1) < k
                    obj.sweep(k,:) = line(x, y, 'Parent', obj.axesHandle, 'Color', obj.sweepColors{k});
                else
                    set(obj.sweep(k,:), 'XData', x, 'YData', y);
                end
                ylabel(obj.axesHandle, units, 'Interpreter', 'none');
            end
            
        end

    end

    methods (Access = private)

        function onSelectedStoreSweep(obj, ~, ~)
            if ~isempty(obj.storedSweep)
                delete(obj.storedSweep);
            end
            obj.storedSweep = copyobj(obj.sweep, obj.axesHandle);
            set(obj.storedSweep, ...
                'Color', obj.storedSweepColor, ...
                'HandleVisibility', 'off');
        end

    end

end
