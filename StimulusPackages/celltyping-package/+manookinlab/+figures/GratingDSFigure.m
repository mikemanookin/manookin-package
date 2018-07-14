classdef GratingDSFigure < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device
        orientations
        temporalFrequency
        preTime
        stimTime
        recordingType
    end
    
    properties (Access = private)
        axesHandle
        yaxis
        repsPerX
        lineHandle
    end
    
    methods
        function obj = GratingDSFigure(device, varargin)
            
            ip = inputParser();
            ip.addParameter('preTime',0.0, @(x)isfloat(x));
            ip.addParameter('stimTime',0.0, @(x)isfloat(x));
            ip.addParameter('recordingType', 'extracellular', @(x)ischar(x));
            ip.addParameter('orientations',[], @(x)isfloat(x));
            ip.addParameter('temporalFrequency',4.0,@(x)isfloat(x));
            ip.parse(varargin{:});

            obj.device = device;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            obj.recordingType = ip.Results.recordingType;
            obj.orientations = ip.Results.orientations;
            obj.temporalFrequency = ip.Results.temporalFrequency;
            
            % Set up the yaxis and reps
            obj.yaxis = zeros(size(obj.orientations));
            obj.repsPerX = zeros(size(obj.orientations));

            obj.createUi();
        end
        
        function createUi(obj)
            import appbox.*;

            obj.axesHandle = axes( ...
                'Parent', obj.figureHandle, ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle, 'orientation');
            ylabel(obj.axesHandle, 'response');
            obj.setTitle('orientation');
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
            title(obj.axesHandle, t);
        end
        
        function clear(obj)
            cla(obj.axesHandle);
            obj.yaxis = zeros(size(obj.orientations));
            obj.repsPerX = zeros(size(obj.orientations));
        end
        
        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                error(['Epoch does not contain a response for ' obj.device.name]);
            end
            
            response = epoch.getResponse(obj.device);
            [quantities, ~] = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            prePts = obj.preTime*1e-3*sampleRate;
            stimPts = obj.stimTime*1e-3*sampleRate;
            xval = epoch.parameters('orientation');
            xIndex = obj.orientations == xval;
            if numel(quantities) > 0
                y = quantities;
                
                if strcmp(obj.recordingType,'extracellular')
                    res = manookinlab.util.spikeDetectorOnline(y,[],sampleRate);
                    y = zeros(size(y));
                    y(res.sp) = sampleRate;
                else
                    if prePts > 0
                        y = y - median(y(1:prePts));
                    else
                        y = y - median(y);
                    end
                end
                
                y = manookinlab.util.binData(y(prePts+1 : prePts+stimPts),100,sampleRate);
                
                r = manookinlab.util.frequencyModulation(y, 100, obj.temporalFrequency, 'avg', 1, []);
                     
                % Iterate the reps.
                obj.repsPerX(xIndex) = obj.repsPerX(xIndex) + 1;
                obj.yaxis(xIndex) = (obj.yaxis(xIndex)*(obj.repsPerX(xIndex)-1) + r)/obj.repsPerX(xIndex);
            end
            
            cla(obj.axesHandle);
            
            % Create your plot.
            obj.lineHandle = polar(obj.axesHandle, obj.orientations/180*pi, obj.yaxis,'ko-');
        end
    end
    
end