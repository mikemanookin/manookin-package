classdef DualSpatialNoiseFigure < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device1
        device2
        recordingType
        numXChecks
        numYChecks
        noiseClass
        chromaticClass
        preTime
        stimTime
        frameRate
        numFrames
        stixelSize
    end
    
    properties (Access = private)
        axesHandle
        imgHandle
        strf1
        strf2
        spaceFilter
        xaxis
        yaxis
    end
    
    methods
        
        function obj = DualSpatialNoiseFigure(device1, device2, varargin)
            ip = inputParser();
            ip.addParameter('recordingType', 'extracellular', @(x)ischar(x));
            ip.addParameter('stixelSize', [], @(x)isfloat(x));
            ip.addParameter('numXChecks', [], @(x)isfloat(x));
            ip.addParameter('numYChecks', [], @(x)isfloat(x));
            ip.addParameter('noiseClass', 'binary', @(x)ischar(x));
            ip.addParameter('chromaticClass', 'achromatic', @(x)ischar(x));
            ip.addParameter('preTime',0.0, @(x)isfloat(x));
            ip.addParameter('stimTime',0.0, @(x)isfloat(x));
            ip.addParameter('frameRate',60.0, @(x)isfloat(x));
            ip.addParameter('numFrames',[], @(x)isfloat(x));
            
            ip.parse(varargin{:});
            
            obj.device1 = device1;
            obj.device2 = device2;
            obj.recordingType = ip.Results.recordingType;
            obj.stixelSize = ip.Results.stixelSize;
            obj.numXChecks = ip.Results.numXChecks;
            obj.numYChecks = ip.Results.numYChecks;
            obj.noiseClass = ip.Results.noiseClass;
            obj.chromaticClass = ip.Results.chromaticClass;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            obj.frameRate = ip.Results.frameRate;
            obj.numFrames = ip.Results.numFrames;
            
            % Set the x/y axes
            obj.xaxis = linspace(-obj.numXChecks/2,obj.numXChecks/2,obj.numXChecks)*obj.stixelSize;
            obj.yaxis = linspace(-obj.numYChecks/2,obj.numYChecks/2,obj.numYChecks)*obj.stixelSize;
            
            obj.createUi();
        end
        
        function createUi(obj)
            import appbox.*;
            
%             obj.axesHandle = axes( ...
%                 'Parent', obj.figureHandle, ...
%                 'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
%                 'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
%                 'XTickMode', 'auto');
            for k = 1 : 4
            obj.axesHandle(k) = subplot(2, 2, k, ...
                'Parent', obj.figureHandle, ...
                'FontUnits', get(obj.figureHandle, 'DefaultUicontrolFontUnits'), ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            end
            
            obj.strf1 = zeros(obj.numYChecks, obj.numXChecks, floor(obj.frameRate*0.5));
            obj.strf2 = zeros(obj.numYChecks, obj.numXChecks, floor(obj.frameRate*0.5));
            obj.spaceFilter = [];
            
            obj.setTitle([obj.device1.name 'receptive field']);
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
%             title(obj.axesHandle, t);
        end
        
        function clear(obj)
            cla(obj.axesHandle);
            obj.strf1 = zeros(obj.numYChecks, obj.numXChecks, floor(obj.frameRate*0.5));
            obj.strf2 = zeros(obj.numYChecks, obj.numXChecks, floor(obj.frameRate*0.5));
            obj.spaceFilter = [];
            % Set the x/y axes
            obj.xaxis = linspace(-obj.numXChecks/2,obj.numXChecks/2,obj.numXChecks)*obj.stixelSize;
            obj.yaxis = linspace(-obj.numYChecks/2,obj.numYChecks/2,obj.numYChecks)*obj.stixelSize;
        end
        
        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device1) || ~epoch.hasResponse(obj.device2)
                error(['Epoch does not contain a response for ' obj.device1.name ' or ' obj.device2.name]);
            end
            
            y1 = getResponseMatrix(epoch.getResponse(obj.device1));
            y2 = getResponseMatrix(epoch.getResponse(obj.device2));
            
            function y = getResponseMatrix(response)
                [quantities, ~] = response.getData();
                sampleRate = response.sampleRate.quantityInBaseUnits;
                prePts = round((obj.preTime*1e-3 - 1/60)*sampleRate);
                if numel(quantities) > 0
                    % Parse the response by type.
                    y = manookinlab.util.responseByType(quantities, obj.recordingType, obj.preTime, sampleRate);

                    if strcmp(obj.recordingType,'extracellular') || strcmp(obj.recordingType, 'spikes_CClamp')
                        y = BinSpikeRate(y(prePts+1:end), obj.frameRate, sampleRate);
                    else
                        % Bandpass filter to get rid of drift.
                        y = bandPassFilter(y, 0.2, 500, 1/sampleRate);
                        if prePts > 0
                            y = y - median(y(1:prePts));
                        else
                            y = y - median(y);
                        end
                        y = binData(y(prePts+1:end), obj.frameRate, sampleRate);
                    end

                    % Make it the same size as the stim frames.
                    y = y(1 : obj.numFrames);

                    % Columate.
                    y = y(:);
                else
                    y = [];
                end
            end
            
            function filterTmp = getSTRF(frameValues, y)
                filterFrames = floor(obj.frameRate*0.5);
                y(1 : floor(obj.frameRate)) = 0;
                
                % Perform reverse correlation.
                if strcmpi(obj.chromaticClass, 'RGB')
                else
                    filterTmp = zeros(obj.numYChecks, obj.numXChecks, filterFrames);
                    for m = 1 : obj.numYChecks
                        for n = 1 : obj.numXChecks
                            tmp = ifft(fft([y; zeros(60,1)]) .* conj(fft([squeeze(frameValues(:,m,n)); zeros(60,1);])));
                            filterTmp(m,n,:) = tmp(1 : filterFrames);
                        end
                    end
                end
            end
            
            if ~isempty(y1)

                % Pull the seed.
                seed = epoch.parameters('seed');
                
                % Get the frame/contrast sequence.
                if strcmpi(obj.noiseClass, 'pink')
                    spatialPower = epoch.parameters('spatialPower');
                    temporalPower = epoch.parameters('temporalPower');
                    frameValues = manookinlab.util.getPinkNoiseFrames(obj.numXChecks, obj.numYChecks, obj.numFrames, ...
                        0.3, spatialPower, temporalPower, seed);
                else
                    frameValues = getSpatialNoiseFrames(obj.numXChecks, obj.numYChecks, ...
                        obj.numFrames, obj.noiseClass, obj.chromaticClass, seed);
                end
                
                % Zero out the first second while cell is adapting to
                % stimulus.
                
                if strcmpi(obj.chromaticClass, 'RGB')
                    frameValues(1 : floor(obj.frameRate),:,:,:) = 0;
                else
                    frameValues(1 : floor(obj.frameRate),:,:) = 0;
                end
                
                obj.strf1 = obj.strf1 + getSTRF(frameValues, y1);
                obj.strf2 = obj.strf2 + getSTRF(frameValues, y2);
                
                
                % Display the spatial RF.
                for k = 1 : 2
                    imagesc('XData',obj.xaxis,'YData',obj.yaxis,...
                        'CData', obj.strf1(:,:,k+3), 'Parent', obj.axesHandle(k));
                    axis(obj.axesHandle(k),'image');
                    colormap(obj.axesHandle(k), 'gray');
                end
                
                for k = 1 : 2
                    imagesc('XData',obj.xaxis,'YData',obj.yaxis,...
                        'CData', obj.strf2(:,:,k+3), 'Parent', obj.axesHandle(k+2));
                    axis(obj.axesHandle(k+2),'image');
                    colormap(obj.axesHandle(k+2), 'gray');
                end
            end
        end
        
    end
end