classdef AdaptFlashFigure < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device
        recordingType
        preTime
        flash1Duration
        flash2Duration
        flash2Contrasts
        ipis
    end
    
    properties (Access = private)
        axesHandle
        xaxis
        yaxis
        repsPerX
        bgResponse
        xName
    end
    
    methods
        function obj = AdaptFlashFigure(device, varargin)
            
            ip = inputParser();
            ip.addParameter('preTime',0.0, @(x)isfloat(x));
            ip.addParameter('flash1Duration',0.0, @(x)isfloat(x));
            ip.addParameter('flash2Duration',0.0, @(x)isfloat(x));
            ip.addParameter('flash2Contrasts',0.0, @(x)isfloat(x));
            ip.addParameter('ipis',0.0, @(x)isfloat(x));
            ip.addParameter('recordingType', 'extracellular', @(x)ischar(x));
            ip.parse(varargin{:});

            obj.device = device;
            obj.preTime = ip.Results.preTime;
            obj.flash1Duration = ip.Results.flash1Duration;
            obj.flash2Duration = ip.Results.flash2Duration;
            obj.flash2Contrasts = ip.Results.flash2Contrasts;
            obj.recordingType = ip.Results.recordingType;
            obj.ipis = ip.Results.ipis;
            
            % Set up the xaxis, yaxis, and reps
            lDur = length(unique(obj.flash2Contrasts));
            iDur = length(unique(obj.ipis));
            if lDur > iDur
                obj.xName = 'flash2Contrast';
                obj.xaxis = unique(obj.flash2Contrasts);
            else
                obj.xName = 'ipi';
                obj.xaxis = unique(obj.ipis);
            end
            obj.yaxis = zeros(size(obj.xaxis));
            obj.repsPerX = zeros(size(obj.xaxis));
            obj.bgResponse = 0;

            obj.createUi();
        end
        
        function createUi(obj)
            import appbox.*;
            
            obj.axesHandle = axes( ...
                'Parent', obj.figureHandle, ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle, obj.xName);
            ylabel(obj.axesHandle, 'response');
            obj.setTitle('adapt flash');
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
            title(obj.axesHandle, t);
        end
        
        function clear(obj)
            cla(obj.axesHandle);
            cla(obj.phaseAxesHandle);
            obj.xaxis = obj.xaxis*0;
            obj.yaxis = zeros(size(obj.xaxis));
            obj.repsPerX = zeros(size(obj.xaxis));
            obj.bgResponse = 0;
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
            
            xval = epoch.parameters(obj.xName);
            xIndex = obj.xaxis == xval;
            
            % Get the ipi for this Epoch.
            ipiTime = epoch.parameters('ipi');
            
            % Get your sample regions.
            prePts = timeToPts(obj.preTime);
            sample = [1 timeToPts(obj.flash2Duration)] + prePts + ...
                timeToPts(obj.flash1Duration + ipiTime);
            
            if numel(quantities) > 0
                % Parse the response by type.
                y = responseByType(quantities, obj.recordingType, obj.preTime, sampleRate);
                
                if prePts > 200
                    if strcmp(obj.recordingType, 'extracellular')
                        obj.bgResponse = mean(y(1 : prePts-200));
                    else
                        y = y - median(y(1 : prePts-200));
                        obj.bgResponse = 0;
                    end
                end
                
                r = mean(y(sample(1) : sample(2))) - obj.bgResponse;
                
                % Iterate the reps.
                obj.repsPerX(xIndex) = obj.repsPerX(xIndex) + 1;
                obj.yaxis(xIndex) = (obj.yaxis(xIndex)*(obj.repsPerX(xIndex)-1) + r)/obj.repsPerX(xIndex);
            end
            
            % Plot the data.
            cla(obj.axesHandle);
            
            line(obj.xaxis, obj.yaxis,...
                'Parent', obj.axesHandle, 'Color', 'k', 'Marker', 'o', 'LineStyle', '-');
            
            set(obj.axesHandle, 'XLim', [min([obj.xaxis(:)',0]) max([obj.xaxis(:)',0])]);
        end
    end
    
end