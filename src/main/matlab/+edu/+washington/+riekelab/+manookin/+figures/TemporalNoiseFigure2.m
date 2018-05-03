classdef TemporalNoiseFigure2 < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device
        recordingType
        preTime
        stimTime
        frameRate
        frameDwell
        noiseClass
        onsets
        durations
        contrasts
    end
    
    properties (Access = private)
        axesHandle
        nlAxesHandle
        lineHandle
        nlHandle
        stimulus1
        stimulus2
        response1
        response2
        nonlinearityBins = 150
    end
    
    methods
        
        function obj = TemporalNoiseFigure2(device, varargin)
            ip = inputParser();
            ip.addParameter('recordingType', 'extracellular', @(x)ischar(x));
            ip.addParameter('noiseClass', 'gaussian', @(x)ischar(x));
            ip.addParameter('preTime',0.0, @(x)isfloat(x));
            ip.addParameter('stimTime',0.0, @(x)isfloat(x));
            ip.addParameter('frameRate',60.0, @(x)isfloat(x));
            ip.addParameter('frameDwell',1, @(x)isfloat(x));
            ip.addParameter('onsets',[], @(x)isfloat(x));
            ip.addParameter('durations',[],@(x)isfloat(x));
            ip.addParameter('contrasts', [], @(x)isfloat(x));
            
            ip.parse(varargin{:});
            
            obj.device = device;
            obj.recordingType = ip.Results.recordingType;
            obj.noiseClass = ip.Results.noiseClass;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            obj.frameRate = ip.Results.frameRate;
            obj.frameDwell = ip.Results.frameDwell;
            obj.onsets = ip.Results.onsets;
            obj.durations = ip.Results.durations;
            obj.contrasts = ip.Results.contrasts;
            obj.noiseClass = ip.Results.noiseClass;
            
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
            
            obj.stimulus1 = [];
            obj.stimulus2 = [];
            obj.response1 = [];
            obj.response2 = [];
            
            obj.setTitle([obj.device.name ': temporal filter']);
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t); 
        end
        
        function clear(obj)
            cla(obj.axesHandle);
            cla(obj.nlAxesHandle);
            obj.stimulus1 = [];
            obj.stimulus2 = [];
            obj.response1 = [];
            obj.response2 = [];
        end
        
        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                error(['Epoch does not contain a response for ' obj.device.name]);
            end
            
            response = epoch.getResponse(obj.device);
            [quantities, ~] = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            prePts = obj.preTime*1e-3*sampleRate;
            % Account for early frame presentation.
            prePts = prePts - round(sampleRate/obj.frameRate);
            
            binRate = 1e3;
            
            if numel(quantities) > 0
                % Parse the response by type.
                y = responseByType(quantities, obj.recordingType, obj.preTime, sampleRate);
                
                if ~strcmp(obj.recordingType,'extracellular') && ~strcmp(obj.recordingType, 'spikes_CClamp')
                    % High-pass filter to get rid of drift.
%                     y = highPassFilter(y, 0.5, 1/sampleRate);
                    if prePts > 0
                        y = y - median(y(1:prePts));
                    else
                        y = y - median(y);
                    end
                end
                
                if sampleRate > binRate
                    y = binData(y(prePts+1:end), binRate, sampleRate);
                else
                    y = y(prePts+1:end);
                end
                
                % Make sure it's a row.
                y = y(:)';

                % Pull the seed.
                seed = epoch.parameters('seed');
                
                %----------------------------------------------------------
                % Get the first frame sequence.
                numFrames = floor(obj.frameRate*obj.durations(1)/obj.frameDwell);
                frameValues = getGaussianNoiseFrames(numFrames, obj.frameDwell, 0.3*obj.contrasts(1), seed);
                
                if binRate > obj.frameRate
                    n = round(binRate / obj.frameRate);
                    frameValues = ones(n,1)*frameValues(:)';
                    frameValues = frameValues(:);
                end
                
                % Make it the same size as the stim frames.
                y1 = y(round(obj.onsets(1)*binRate)+ (1 : length(frameValues)));
                
                % Zero out the first half-second while cell is adapting to
                % stimulus.
                y1(1 : floor(binRate/2)) = 0;
                frameValues(1 : floor(binRate/2)) = 0;
                
                obj.stimulus1 = [obj.stimulus1; frameValues(:)'];
                obj.response1 = [obj.response1; y1(:)'];
                
                % Calculate the linear filter.
                lf1 = real(ifft(mean((fft(obj.response1,[],2).*conj(fft(obj.stimulus1,[],2))),1)));
                lf1 = lf1 / max(abs(lf1));
                
                % Calculate the linear prediction.
                prediction = zeros(size(obj.response1));
                for n = 1 : size(obj.stimulus1,1)
                    prediction(n,:) = real(ifft(fft(lf1) .* fft(obj.stimulus1(n,:))));
                end
                prediction(isnan(prediction))=0;
                
                % Bin the nonlinearity
                [xBin1, yBin1] = binNonlinearity(prediction, obj.response1, obj.nonlinearityBins); 
                
                if length(obj.durations) > 1
                    numFrames = floor(obj.frameRate*obj.durations(2)/obj.frameDwell);
                    frameValues = getGaussianNoiseFrames(numFrames, obj.frameDwell, 0.3*obj.contrasts(2), seed);

                    if binRate > obj.frameRate
                        n = round(binRate / obj.frameRate);
                        frameValues = ones(n,1)*frameValues(:)';
                        frameValues = frameValues(:);
                    end

                    % Make it the same size as the stim frames.
                    y2 = y(round(obj.onsets(2)*binRate)+ (1 : length(frameValues)));

                    % Zero out the first half-second while cell is adapting to
                    % stimulus.
                    y2(1 : floor(binRate/2)) = 0;
                    frameValues(1 : floor(binRate/2)) = 0;

                    obj.stimulus2 = [obj.stimulus2; frameValues(:)'];
                    obj.response2 = [obj.response2; y2(:)'];
                    
                    % Calculate the linear filter.
                    lf2 = real(ifft(mean((fft(obj.response2,[],2).*conj(fft(obj.stimulus2,[],2))),1)));
                    lf2 = lf2 / max(abs(lf2));
                    % Calculate the linear prediction.
                    prediction = zeros(size(obj.response2));
                    for n = 1 : size(obj.stimulus2,1)
                        prediction(n,:) = real(ifft(fft(lf2) .* fft(obj.stimulus2(n,:))));
                    end
                    prediction(isnan(prediction))=0;
                    % Bin the nonlinearity
                    [xBin2, yBin2] = binNonlinearity(prediction, obj.response2, obj.nonlinearityBins); 
                end
                
                plotLngth = floor(binRate/2);
                
                % Plot the data.
                cla(obj.axesHandle);
                line((1:plotLngth)/binRate, lf1(1:plotLngth),...
                    'Parent', obj.axesHandle, 'Color', 'k');
                if length(obj.durations) > 1
                    hold(obj.axesHandle, 'on');
                    line((1:plotLngth)/binRate, lf2(1:plotLngth),...
                        'Parent', obj.axesHandle, 'Color', [0.8 0 0]);
                    hold(obj.axesHandle, 'off');
                end 
                axis(obj.axesHandle, 'tight');
                
                cla(obj.nlAxesHandle);
                line(xBin1, yBin1, ...
                    'Parent', obj.nlAxesHandle, 'Color', 'k', 'Marker', '.');
                if length(obj.durations) > 1
                    hold(obj.nlAxesHandle, 'on');
                    line(xBin2, yBin2, ...
                        'Parent', obj.nlAxesHandle, 'Color', [0.8 0 0], 'Marker', '.');
                    hold(obj.nlAxesHandle, 'off');
                end
                axis(obj.nlAxesHandle, 'tight');
            end
        end  
    end
end