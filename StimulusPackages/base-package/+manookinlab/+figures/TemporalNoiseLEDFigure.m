classdef TemporalNoiseLEDFigure < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device
        recordingType
        preTime
        stimTime
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
        
        function obj = TemporalNoiseLEDFigure(device, varargin)
            ip = inputParser();
            ip.addParameter('recordingType', 'extracellular', @(x)ischar(x));
            ip.addParameter('preTime',0.0, @(x)isfloat(x));
            ip.addParameter('stimTime',0.0, @(x)isfloat(x));
            
            ip.parse(varargin{:});
            
            obj.device = device;
            obj.recordingType = ip.Results.recordingType;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;

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
            
            obj.xaxis = zeros(1,obj.nonlinearityBins);
            obj.yaxis = zeros(1,obj.nonlinearityBins);
            
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
            
            binRate = 1000;
            
            disp('I am here...');
            
            response = epoch.getResponse(obj.device);
            [quantities, ~] = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            prePts = obj.preTime*1e-3*sampleRate;
            stimPts = obj.stimTime*1e-3*sampleRate;
            disp('Calculated points...');
            
            disp(stimPts);
            
            disp(numel(quantities));
            
            if numel(quantities) > 0
                % Parse the response by type.
                y = manookinlab.util.responseByType(quantities, obj.recordingType, obj.preTime, sampleRate);
                
                disp('Got the data');
                disp(numel(y))
                
                if strcmp(obj.recordingType,'extracellular') || strcmp(obj.recordingType, 'spikes_CClamp')
                    if sampleRate > binRate
                        y = manookinlab.util.BinSpikeRate(y(prePts+(1:stimPts))/sampleRate, binRate, sampleRate);
                    else
                        y = y(prePts+(1:stimPts));
                    end
                else
                    % High-pass filter to get rid of drift.
%                     y = highPassFilter(y, 0.5, 1/sampleRate);
                    if prePts > 0
                        y = y - median(y(1:prePts));
                    else
                        y = y - median(y);
                    end
                    y = manookinlab.util.binData(y(prePts+(1:stimPts)), binRate, sampleRate);
                end
                
                % Make sure it's a row.
                y = y(:)';
                
                disp(['Got the data',num2str(size(y))]);
                
                preBins = obj.preTime*1e-3*binRate;
                stimBins = obj.stimTime*1e-3*binRate;

                % Pull the contrast sequence.
                frameValues = epoch.parameters('contrast');
                frameValues = frameValues(preBins+(1:stimBins));
                
                disp('Got the frame values...');
                
                disp(numel(frameValues));
                
                
                % Make it the same size as the stim frames.
                y = y(1 : length(frameValues));
                
                size(y)
                size(frameValues)
                
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
                gbIndex = 1;
                
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
                [xBin, yBin] = obj.getNL(obj.P(:,floor(binRate/2)+1:end), obj.R(:,floor(binRate/2)+1:end));
                obj.xaxis(gbIndex,:) = xBin;
                obj.yaxis(gbIndex,:) = yBin;

                % Plot the data.
                plotLngth = 5000;
                cla(obj.axesHandle);
                obj.lineHandle = line((1:plotLngth)/binRate, obj.linearFilter(1:plotLngth),...
                    'Parent', obj.axesHandle, 'Color', 'k');
                
                axis(obj.axesHandle, 'tight');
                title(obj.axesHandle, ['Max/min output: ', num2str(max(abs(obj.yaxis(:))))]);
                
                cla(obj.nlAxesHandle);
                
                obj.nlHandle = line(xBin, yBin, ...
                    'Parent', obj.nlAxesHandle, 'Color', 'k');
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