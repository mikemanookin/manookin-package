classdef TemporalNoiseFigure < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device
        recordingType
        preTime
        stimTime
        frameRate
        numFrames
        frameDwell
        stdev
        frequencyCutoff
        numberOfFilters
        correlation
        noiseClass
        stimulusClass
        groupBy
        groupByValues
    end
    
    properties (Access = private)
        axesHandle
        nlAxesHandle
        lineHandle
        nlHandle
        linearFilter
        xaxis
        yaxis
        epochCount
        nonlinearityBins = 100
        S
        P
        R
        gbVals
    end
    
    methods
        
        function obj = TemporalNoiseFigure(device, varargin)
            ip = inputParser();
            ip.addParameter('recordingType', 'extracellular', @(x)ischar(x));
            ip.addParameter('noiseClass', 'gaussian', @(x)ischar(x));
            ip.addParameter('preTime',0.0, @(x)isfloat(x));
            ip.addParameter('stimTime',0.0, @(x)isfloat(x));
            ip.addParameter('frameRate',60.0, @(x)isfloat(x));
            ip.addParameter('numFrames',[], @(x)isfloat(x));
            ip.addParameter('frameDwell',1, @(x)isfloat(x));
            ip.addParameter('stdev', 0.3, @(x)isfloat(x));
            ip.addParameter('frequencyCutoff',0.0, @(x)isfloat(x));
            ip.addParameter('numberOfFilters', 0, @(x)isfloat(x));
            ip.addParameter('correlation', 0.0, @(x)isfloat(x));
            ip.addParameter('stimulusClass','Stage',@(x)ischar(x));
            ip.addParameter('groupBy','',@(x)ischar(x));
            ip.addParameter('groupByValues',{},@(x)iscellstr(x));
            
            ip.parse(varargin{:});
            
            obj.device = device;
            obj.recordingType = ip.Results.recordingType;
            obj.noiseClass = ip.Results.noiseClass;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            obj.frameRate = ip.Results.frameRate;
            obj.numFrames = ip.Results.numFrames;
            obj.frameDwell = ip.Results.frameDwell;
            obj.stdev = ip.Results.stdev;
            obj.frequencyCutoff = ip.Results.frequencyCutoff;
            obj.numberOfFilters = ip.Results.numberOfFilters;
            obj.correlation = ip.Results.correlation;
            obj.stimulusClass = ip.Results.stimulusClass;
            obj.groupBy = ip.Results.groupBy;
            obj.groupByValues = ip.Results.groupByValues;
            
            % Check the stimulus class.
            if strcmpi(obj.stimulusClass, 'Stage') || strcmpi(obj.stimulusClass, 'spatial')
                obj.stimulusClass = 'Stage';
            else
                obj.stimulusClass = 'Injection';
            end
            obj.epochCount = 0;
            
            obj.createUi();
        end
        
        function createUi(obj)
            import appbox.*;
            
            obj.axesHandle = subplot(1, 3, 1:2, ...
                'Parent', obj.figureHandle, ...
                'FontUnits', get(obj.figureHandle, 'DefaultUicontrolFontUnits'), ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            
            obj.nlAxesHandle = subplot(1, 3, 3, ...
                'Parent', obj.figureHandle, ...
                'FontUnits', get(obj.figureHandle, 'DefaultUicontrolFontUnits'), ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto'); 
            
            obj.linearFilter = [];
            
            obj.epochCount = 0;
            obj.P = [];
            obj.R = [];
            obj.S = [];
            obj.gbVals = {};
            
            if isempty(obj.groupBy)
                obj.xaxis = zeros(1,obj.nonlinearityBins);
                obj.yaxis = zeros(1,obj.nonlinearityBins);
            else
                obj.xaxis = zeros(length(obj.groupByValues),obj.nonlinearityBins);
                obj.yaxis = zeros(length(obj.groupByValues),obj.nonlinearityBins);
            end
            
            obj.setTitle([obj.device.name ': temporal filter']);
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t); 
        end
        
        function clear(obj)
            cla(obj.axesHandle);
            cla(obj.nlAxesHandle);
            obj.linearFilter = [];
            % Set the x/y axes
            obj.xaxis = 0*obj.xaxis;
            obj.yaxis = 0*obj.yaxis;
            obj.P = [];
            obj.R = [];
            obj.S = [];
            obj.gbVals = {};
        end
        
        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                error(['Epoch does not contain a response for ' obj.device.name]);
            end
            
            obj.epochCount = obj.epochCount + 1;
            
            response = epoch.getResponse(obj.device);
            [quantities, ~] = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            prePts = obj.preTime*1e-3*sampleRate;
            stimPts = obj.stimTime*1e-3*sampleRate;
            
            if strcmpi(obj.stimulusClass, 'Stage')
                binRate = 10000;
                % Account for early frame presentation.
                prePts = prePts - round(sampleRate/obj.frameRate);
            else
                binRate = 480;
            end
            
            if numel(quantities) > 0
                % Parse the response by type.
                y = manookinlab.util.responseByType(quantities, obj.recordingType, obj.preTime, sampleRate);
                
                if strcmp(obj.recordingType,'extracellular') || strcmp(obj.recordingType, 'spikes_CClamp')
                    if sampleRate > binRate
                        y = manookinlab.util.BinSpikeRate(y(prePts+1:end)/sampleRate, binRate, sampleRate);
                    else
                        y = y(prePts+1:end);
                    end
                else
                    % High-pass filter to get rid of drift.
%                     y = highPassFilter(y, 0.5, 1/sampleRate);
                    if prePts > 0
                        y = y - median(y(1:prePts));
                    else
                        y = y - median(y);
                    end
                    y = manookinlab.util.binData(y(prePts+1:end), binRate, sampleRate);
                end
                
                % Make sure it's a row.
                y = y(:)';

                % Pull the seed.
                seed = epoch.parameters('seed');
                
                % Get the frame/current sequence.
                if strcmpi(obj.stimulusClass, 'Stage')
                    
                    frameValues = manookinlab.util.getGaussianNoiseFrames(obj.numFrames, obj.frameDwell, obj.stdev, seed);
                    
                    if binRate > obj.frameRate
                        n = round(binRate / obj.frameRate);
                        frameValues = ones(n,1)*frameValues(:)';
                        frameValues = frameValues(:);
                    end
                    plotLngth = round(binRate*0.5);
                else
                    frameValues = obj.generateCurrentStim(sampleRate, seed);
                    frameValues = frameValues(prePts+1:stimPts);
                    if sampleRate > binRate
                        frameValues = decimate(frameValues, round(sampleRate/binRate));
                    end
                    plotLngth = round(binRate*0.025);
                end
                
                % Make it the same size as the stim frames.
                y = y(1 : length(frameValues));
                
                % Zero out the first half-second while cell is adapting to
                % stimulus.
                y(1 : floor(binRate/2)) = 0;
                frameValues(1 : floor(binRate/2)) = 0;
                
                obj.R(obj.epochCount,:) = y(:)';
                obj.S(obj.epochCount,:) = frameValues(:)';
                
                % Reverse correlation.
                lf  = real(ifft(mean((fft([obj.R,zeros(size(obj.R,1),100)],[],2) .* conj(fft([obj.S,zeros(size(obj.S,1),100)],[],2))),1)));
%                 lf = real(ifft( fft([y(:)' zeros(1,100)]) .* conj(fft([frameValues(:)' zeros(1,100)])) ));
%                 lf = lf(1 : length(y));
                lf = lf/norm(lf);
                
                obj.linearFilter = lf;
                
%                 if isempty(obj.linearFilter)
%                     obj.linearFilter = lf;
%                 else
%                     obj.linearFilter = (obj.linearFilter*(obj.epochCount-1) + lf)/obj.epochCount;
%                 end
                
                % Get the groupBy value for this Epoch.
                if ~isempty(obj.groupBy)
                    gbValue = epoch.parameters(obj.groupBy);
                    [tf,gbIndex] = ismember(gbValue,obj.groupByValues);
                    if ~tf
                        gbIndex = 1;
                    end
                    obj.gbVals = [obj.gbVals, gbValue];
                else
                    gbIndex = 1;
                end
                
                % Compute the linear prediction.
                if obj.epochCount < 25 && obj.epochCount > 1
                    for k = 1 : size(obj.S,1)
                        pred = ifft(fft([obj.S(k,:) zeros(1,100)]) .* fft(obj.linearFilter(:)'));
                        pred=pred(:)';
                        obj.P(k,:) = pred(1:length(y));
                    end
                else
                    % Convolve stimulus with filter to get generator signal.
                    pred = ifft(fft([frameValues(:)' zeros(1,100)]) .* fft(obj.linearFilter(:)'));
                    pred=pred(:)';
                    obj.P(obj.epochCount,:) = pred(1:length(y));
                end                
                
                % Get the binned nonlinearity.
                if ~isempty(obj.groupBy)
                    index = strcmp(obj.gbVals,gbValue);
                    [xBin, yBin] = obj.getNL(obj.P(index,floor(binRate/2)+1:end), obj.R(index,floor(binRate/2)+1:end));
                else
                    [xBin, yBin] = obj.getNL(obj.P(:,floor(binRate/2)+1:end), obj.R(:,floor(binRate/2)+1:end));
                end
                obj.xaxis(gbIndex,:) = xBin;
                obj.yaxis(gbIndex,:) = yBin;

                % Plot the data.
                cla(obj.axesHandle);
                obj.lineHandle = line((1:plotLngth)/binRate, obj.linearFilter(1:plotLngth),...
                    'Parent', obj.axesHandle, 'Color', 'k');
                if ~strcmpi(obj.stimulusClass, 'Stage')
                    hold(obj.axesHandle, 'on');
                    line((1:round(binRate*0.25))/binRate/10, obj.linearFilter(1:round(binRate*0.25)),...
                        'Parent', obj.axesHandle, 'Color', 'r');
                    hold(obj.axesHandle, 'off');
                end
                
                axis(obj.axesHandle, 'tight');
                title(obj.axesHandle, ['Max/min output: ', num2str(max(abs(obj.yaxis(:))))]);
                
                cla(obj.nlAxesHandle);
                
                if ~isempty(obj.groupBy)
                    axColors = [0 0 0; 0.8 0 0; 0 0.5 0; 0 0 1; 1 0 0];
                    for k = 1 : size(obj.yaxis,1)
                        line(obj.xaxis(k,:), obj.yaxis(k,:),...
                            'Parent', obj.nlAxesHandle, 'Color', axColors(k,:), 'LineStyle', '-');
                    end
                    legend(obj.nlAxesHandle,obj.groupByValues,'Location','NorthWest');
                else
                    obj.nlHandle = line(xBin, yBin, ...
                        'Parent', obj.nlAxesHandle, 'Color', 'k');
                end
                axis(obj.nlAxesHandle, 'tight');
            end
        end
        
        function stimValues = generateCurrentStim(obj, sampleRate, seed)
            gen = manookinlab.stimuli.GaussianNoiseGeneratorV2();
            
            gen.preTime = obj.preTime;
            gen.stimTime = obj.stimTime;
            gen.tailTime = 100;
            gen.stDev = obj.stdev;
            gen.freqCutoff = obj.frequencyCutoff;
            gen.numFilters = obj.numberOfFilters;
            gen.mean = 0;
            gen.seed = seed;
            gen.sampleRate = sampleRate;
            gen.units = 'pA';
            
            stim = gen.generate();
            stimValues = stim.getData();
        end
        
        function [xBin, yBin] = getNL(obj, P, R)
            % Sort the data; xaxis = prediction; yaxis = response;
            [a, b] = sort(P(:));
            R = R(:);
            xSort = a;
            ySort = R(b);

            % Bin the data.
            valsPerBin = floor(length(xSort) / obj.nonlinearityBins);
            xBin = mean(reshape(xSort(1 : obj.nonlinearityBins*valsPerBin),valsPerBin,obj.nonlinearityBins));
            yBin = mean(reshape(ySort(1 : obj.nonlinearityBins*valsPerBin),valsPerBin,obj.nonlinearityBins));
        end
        
    end
end