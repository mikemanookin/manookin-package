classdef JitteredNoiseFigure < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device
        recordingType
        numXChecks
        numYChecks
        preTime
        stimTime
        frameRate
        numFrames
        stixelSize
        stepsPerStixel
    end
    
    properties (Access = private)
        axesHandle
        imgHandle
        strf
        spaceFilter
        xaxis
        yaxis
    end
    
    methods
        
        function obj = JitteredNoiseFigure(device, varargin)
            ip = inputParser();
            ip.addParameter('recordingType', 'extracellular', @(x)ischar(x));
            ip.addParameter('stixelSize', [], @(x)isfloat(x));
            ip.addParameter('numXChecks', [], @(x)isfloat(x));
            ip.addParameter('numYChecks', [], @(x)isfloat(x));
            ip.addParameter('preTime',0.0, @(x)isfloat(x));
            ip.addParameter('stimTime',0.0, @(x)isfloat(x));
            ip.addParameter('frameRate',60.0, @(x)isfloat(x));
            ip.addParameter('numFrames',[], @(x)isfloat(x));
            ip.addParameter('stepsPerStixel',4, @(x)isfloat(x));
            
            ip.parse(varargin{:});
            
            obj.device = device;
            obj.recordingType = ip.Results.recordingType;
            obj.stixelSize = ip.Results.stixelSize;
            obj.numXChecks = ip.Results.numXChecks;
            obj.numYChecks = ip.Results.numYChecks;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            obj.frameRate = ip.Results.frameRate;
            obj.numFrames = ip.Results.numFrames;
            obj.stepsPerStixel = ip.Results.stepsPerStixel;
            
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
            
            obj.strf = zeros(obj.numYChecks, obj.numXChecks, floor(obj.frameRate*0.5));
            obj.spaceFilter = [];
            
            obj.setTitle([obj.device.name 'receptive field']);
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
%             title(obj.axesHandle, t);
        end
        
        function clear(obj)
            cla(obj.axesHandle);
            obj.strf = zeros(obj.numYChecks, obj.numXChecks, floor(obj.frameRate*0.5));
            obj.spaceFilter = [];
            % Set the x/y axes
            obj.xaxis = linspace(-obj.numXChecks/2,obj.numXChecks/2,obj.numXChecks)*obj.stixelSize;
            obj.yaxis = linspace(-obj.numYChecks/2,obj.numYChecks/2,obj.numYChecks)*obj.stixelSize;
        end
        
        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                error(['Epoch does not contain a response for ' obj.device.name]);
            end
            
            response = epoch.getResponse(obj.device);
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

                % Pull the seed.
                seed = epoch.parameters('seed');
                numXStixels = epoch.parameters('numXStixels');
                numYStixels = epoch.parameters('numYStixels');
                
                % Get the frame/contrast sequence.
                frameValues = manookinlab.util.getJitteredNoiseFrames(numXStixels, numYStixels, obj.numXChecks, obj.numYChecks, obj.numFrames, obj.stepsPerStixel, seed);
                
                % Zero out the first second while cell is adapting to
                % stimulus.
                y(1 : floor(obj.frameRate)) = 0;
                frameValues(:,:,1 : floor(obj.frameRate)) = 0;
                frameValues(:,:,end-14:end) = 0;
                y(end-14:end) = 0;
                
                filterFrames = floor(obj.frameRate*0.5);
                lobePts = 2:4; %round(0.03*obj.frameRate) : round(0.15*obj.frameRate);
                
                % Perform reverse correlation.
                filterTmp = zeros(obj.numYChecks, obj.numXChecks, filterFrames);
                for m = 1 : obj.numYChecks
                    for n = 1 : obj.numXChecks
                        tmp = ifft(fft([y; zeros(60,1)]) .* conj(fft([squeeze(frameValues(m,n,:)); zeros(60,1);])));
                        filterTmp(m,n,:) = tmp(1 : filterFrames);
                    end
                end
                obj.strf = obj.strf + filterTmp;
                obj.spaceFilter = squeeze(mean(obj.strf(:,:,lobePts),3));
                
                % Display the spatial RF.
                for k = 1 : 4
                    imagesc('XData',obj.xaxis,'YData',obj.yaxis,...
                        'CData', obj.strf(:,:,k+2), 'Parent', obj.axesHandle(k));
                    axis(obj.axesHandle(k),'image');
                    colormap(obj.axesHandle(k), 'gray');
                    title(obj.axesHandle(k),['t: -',num2str(round((k+1)/obj.frameRate*1000)),' ms']);
                end
            end
        end
        
    end
end