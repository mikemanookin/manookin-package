classdef SpatialNoiseFigure < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device
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
        strf
        spaceFilter
        xaxis
        yaxis
    end
    
    methods
        
        function obj = SpatialNoiseFigure(device, varargin)
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
            
            obj.device = device;
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
            
            obj.axesHandle = axes( ...
                'Parent', obj.figureHandle, ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            
            obj.strf = zeros(obj.numYChecks, obj.numXChecks, floor(obj.frameRate*0.5));
            obj.spaceFilter = [];
            
            obj.setTitle([obj.device.name 'receptive field']);
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
            title(obj.axesHandle, t);
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
                y = responseByType(quantities, obj.recordingType, obj.preTime, sampleRate);
                
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
                
                % Get the frame/contrast sequence.
                frameValues = getSpatialNoiseFrames(obj.numXChecks, obj.numYChecks, ...
                    obj.numFrames, obj.noiseClass, obj.chromaticClass, seed);
                
                % Zero out the first second while cell is adapting to
                % stimulus.
                y(1 : floor(obj.frameRate)) = 0;
                if strcmpi(obj.chromaticClass, 'RGB')
                    frameValues(1 : floor(obj.frameRate),:,:,:) = 0;
                else
                    frameValues(1 : floor(obj.frameRate),:,:) = 0;
                end
                
                filterFrames = floor(obj.frameRate*0.5);
                lobePts = 2:4; %round(0.03*obj.frameRate) : round(0.15*obj.frameRate);
                
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
                    obj.strf = obj.strf + filterTmp;
                    if obj.numXChecks == 1 || obj.numYChecks == 1
                        obj.spaceFilter = squeeze(obj.strf);
                    else
                        obj.spaceFilter = squeeze(mean(obj.strf(:,:,lobePts),3));
                    end
                end
                
                % Display the spatial RF.
                if obj.numXChecks == 1 || obj.numYChecks == 1
                    obj.imgHandle = imagesc(obj.spaceFilter, 'Parent', obj.axesHandle);
                else
                    obj.imgHandle = imagesc('XData',obj.xaxis,'YData',obj.yaxis,...
                        'CData', obj.spaceFilter, 'Parent', obj.axesHandle);
                    axis(obj.axesHandle, 'image');
                end
                colormap(obj.axesHandle, 'gray');
            end
        end
        
    end
end