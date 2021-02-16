classdef FlashMapperFigure < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device
        recordingType
        preTime
        stimTime
        stixelSize
        gridWidth
    end
    
    properties (Access = private)
        axesHandle
        imgHandle
        xvals
        yvals
        strf
    end
    
    methods
        
        function obj = FlashMapperFigure(device, varargin)
            ip = inputParser();
            ip.addParameter('recordingType', 'extracellular', @(x)ischar(x));
            ip.addParameter('preTime',0.0, @(x)isfloat(x));
            ip.addParameter('stimTime',0.0, @(x)isfloat(x));
            ip.addParameter('stixelSize',50.0, @(x)isfloat(x));
            ip.addParameter('gridWidth',300.0, @(x)isfloat(x));
            
            ip.parse(varargin{:});
            
            obj.device = device;
            obj.recordingType = ip.Results.recordingType;
            obj.stixelSize = ip.Results.stixelSize;
            obj.gridWidth = ip.Results.gridWidth;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            
            % Meshgrid.
            edgeChecks = ceil(obj.gridWidth / obj.stixelSize);
            [obj.xvals,obj.yvals] = meshgrid(linspace(-obj.stixelSize*edgeChecks/2+obj.stixelSize/2,obj.stixelSize*edgeChecks/2-obj.stixelSize/2,edgeChecks));
            
            obj.createUi();
        end
        
        function createUi(obj)
            import appbox.*;
            
%             obj.axesHandle = axes( ...
%                 'Parent', obj.figureHandle, ...
%                 'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
%                 'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
%                 'XTickMode', 'auto');
            for k = 1 : 2
            obj.axesHandle(k) = subplot(1, 2, k, ...
                'Parent', obj.figureHandle, ...
                'FontUnits', get(obj.figureHandle, 'DefaultUicontrolFontUnits'), ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            end
            
            obj.strf = zeros(size(obj.xvals,1), size(obj.xvals,2), 2);
            
            obj.setTitle([obj.device.name 'receptive field']);
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
%             title(obj.axesHandle, t);
        end
        
        function clear(obj)
            cla(obj.axesHandle);
            obj.strf = zeros(size(obj.xvals,1), size(obj.xvals,2), 2);
        end
        
        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                error(['Epoch does not contain a response for ' obj.device.name]);
            end
            
            response = epoch.getResponse(obj.device);
            [quantities, ~] = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            prePts = round((obj.preTime*1e-3)*sampleRate);
            stimPts = round((obj.stimTime*1e-3)*sampleRate);
            
            if numel(quantities) > 0
                % Parse the response by type.
                y = manookinlab.util.responseByType(quantities, obj.recordingType, obj.preTime, sampleRate);
                
                if strcmp(obj.recordingType,'extracellular') || strcmp(obj.recordingType, 'spikes_CClamp')
                    y = BinSpikeRate(y, 60, sampleRate);
                else
                    % Bandpass filter to get rid of drift.
                    y = bandPassFilter(y, 0.2, 500, 1/sampleRate);
                    if prePts > 0
                        y = y - median(y(1:prePts));
                    else
                        y = y - median(y);
                    end
                    y = binData(y, 60, sampleRate);
                end
                
                y = mean(y(prePts+(1:stimPts)));
                
                % Pull the seed.
                position = epoch.parameters('position');
                stimContrast = epoch.parameters('stimContrast');
                
                [row,col] = find(x == position(1) & y == position(2),1);
                
                if stimContrast < 0
                    obj.strf(row,col,1) = obj.strf(row,col,1) + y;
                else
                    obj.strf(row,col,2) = obj.strf(row,col,2) + y;
                end
                
                % Display the spatial RF.
                for k = 1 : 2
                    imagesc('XData',unique(obj.xvals),'YData',unique(obj.yvals),...
                        'CData', obj.strf(:,:,k), 'Parent', obj.axesHandle(k));
                    axis(obj.axesHandle(k),'image');
                    colormap(obj.axesHandle(k), 'gray');
                    if k == 1
                        title(obj.axesHandle(k),'negative contrast');
                    else
                        title(obj.axesHandle(k),'positive contrast');
                    end
                end
            end
        end
        
    end
end