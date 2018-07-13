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
        nonlinearityBins = 200
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
            obj.xaxis = [];
            obj.yaxis = [];
            obj.epochCount = 0;
            
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
            obj.xaxis = [];
            obj.yaxis = [];
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
                y = responseByType(quantities, obj.recordingType, obj.preTime, sampleRate);
                
                if strcmp(obj.recordingType,'extracellular') || strcmp(obj.recordingType, 'spikes_CClamp')
                    if sampleRate > binRate
                        y = BinSpikeRate(y(prePts+1:end), binRate, sampleRate);
                    else
                        y = y(prePts+1:end)*sampleRate;
                    end
                else
                    % High-pass filter to get rid of drift.
%                     y = highPassFilter(y, 0.5, 1/sampleRate);
                    if prePts > 0
                        y = y - median(y(1:prePts));
                    else
                        y = y - median(y);
                    end
                    y = binData(y(prePts+1:end), binRate, sampleRate);
                end
                
                % Make sure it's a row.
                y = y(:)';

                % Pull the seed.
                seed = epoch.parameters('seed');
                
                % Get the frame/current sequence.
                if strcmpi(obj.stimulusClass, 'Stage')
                    frameValues = getGaussianNoiseFrames(obj.numFrames, obj.frameDwell, obj.stdev, seed);
                    
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
                
                % Reverse correlation.
                lf = real(ifft( fft([y(:)' zeros(1,100)]) .* conj(fft([frameValues(:)' zeros(1,100)])) ));
                
                if isempty(obj.linearFilter)
                    obj.linearFilter = lf;
                else
                    obj.linearFilter = (obj.linearFilter*(obj.epochCount-1) + lf)/obj.epochCount;
                end
                
                % Re-bin the response for the nonlinearity.
                resp = binData(y, 60, binRate);
                obj.yaxis = [obj.yaxis, resp(:)'];
                
                % Convolve stimulus with filter to get generator signal.
                pred = ifft(fft([frameValues(:)' zeros(1,100)]) .* fft(obj.linearFilter(:)'));
                
                pred = binData(pred, 60, binRate); pred=pred(:)';
                obj.xaxis = [obj.xaxis, pred(1 : length(resp))];
                
                % Get the binned nonlinearity.
                [xBin, yBin] = obj.getNL(obj.xaxis, obj.yaxis);
                
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
                obj.nlHandle = line(xBin, yBin, ...
                    'Parent', obj.nlAxesHandle, 'Color', 'k', 'Marker', '.');
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
            xSort = a;
            ySort = R(b);

            % Bin the data.
            valsPerBin = floor(length(xSort) / obj.nonlinearityBins);
            xBin = mean(reshape(xSort(1 : obj.nonlinearityBins*valsPerBin),valsPerBin,obj.nonlinearityBins));
            yBin = mean(reshape(ySort(1 : obj.nonlinearityBins*valsPerBin),valsPerBin,obj.nonlinearityBins));
        end
        
    end
end