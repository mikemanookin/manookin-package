classdef AdaptGratingFigure < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device
        recordingType
        preTime
        highTime
        numSubplots
    end
    
    properties (Access = private)
        axesHandle
        sweeps
        epochTags
        meanLine
        highLine
    end
    
    methods
        
        function obj = AdaptGratingFigure(device, varargin)
            ip = inputParser();
            ip.addParameter('recordingType', 'extracellular', @(x)ischar(x));
            ip.addParameter('preTime',0.0, @(x)isfloat(x));
            ip.addParameter('highTime',0.0, @(x)isfloat(x));
            ip.addParameter('numSubplots',4, @(x)isfloat(x));
            
            ip.parse(varargin{:});
            
            obj.device = device;
            obj.recordingType = ip.Results.recordingType;
            obj.preTime = ip.Results.preTime;
            obj.highTime = ip.Results.highTime;
            obj.numSubplots = ip.Results.numSubplots;
            
            obj.createUi();
        end
        
        function createUi(obj)
            import appbox.*;
            
            obj.axesHandle = {};
            if length(obj.numSubplots) <= 2
                nrows=2; ncols=1;
            elseif length(obj.numSubplots) <= 4
                nrows=2; ncols=2;
            elseif length(obj.numSubplots) <= 6
                nrows=3; ncols=2;
            else
                nrows=3; ncols=3;
            end
            for k = 1 : min(obj.numSubplots,9)
                obj.axesHandle{k} = subplot(nrows, ncols, k, ...
                    'Parent', obj.figureHandle, ...
                    'FontUnits', get(obj.figureHandle, 'DefaultUicontrolFontUnits'), ...
                    'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                    'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                    'XTickMode', 'auto');
                xlabel(obj.axesHandle{k},'sec');
            end
            
            obj.sweeps = [];
            obj.epochTags = {};
            
            obj.setTitle([obj.device.name ': adaptation']);
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t); 
        end
        
        function clear(obj)
            for k = 1 : length(obj.axesHandle)
                cla(obj.axesHandle{k});
            end
            obj.sweeps = [];
            obj.epochTags = {};
        end
        
        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                error(['Epoch does not contain a response for ' obj.device.name]);
            end
            
            response = epoch.getResponse(obj.device);
            [quantities, ~] = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            prePts = obj.preTime*1e-3;
            highPts = obj.highTime*1e-3;
            
            if numel(quantities) > 0
                % Parse the response by type.
                y = responseByType(quantities, obj.recordingType, obj.preTime, sampleRate);
                y = rand(1,length(y));
                epochTag = epoch.parameters('epochTag');
                obj.sweeps = [obj.sweeps; y(:)'];
                obj.epochTags{end+1} = epochTag;
                
                % Plot the data.
                % Get the unique tags.
                utags = unique(obj.epochTags);
                
                for k = 1 : min(length(utags),9)
                    trIndex = find(strcmp(obj.epochTags,utags{k}));
                    
                    cla(obj.axesHandle{k});
                    hold(obj.axesHandle{k}, 'on');
                    obj.meanLine = line((1:size(obj.sweeps,2))/sampleRate,mean(obj.sweeps(trIndex,:),1),...
                        'Color','k','Parent',obj.axesHandle{k},'DisplayName','mean'); axis(obj.axesHandle{k},'tight');
                    obj.highLine = line(prePts+highPts*ones(1,2),get(obj.axesHandle{k},'YLim'),'Color',[204 0 0]/255,'Parent',obj.axesHandle{k},'DisplayName','end');
                    hold(obj.axesHandle{k},'off');
                    xlabel(obj.axesHandle{k},'sec');
                    title(obj.axesHandle{k},utags{k});
                end
            end
        end
    end
end