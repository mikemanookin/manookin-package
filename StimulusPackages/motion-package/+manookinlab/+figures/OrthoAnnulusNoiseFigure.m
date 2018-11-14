classdef OrthoAnnulusNoiseFigure < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device
        recordingType
        preTime
        stimTime
        frameRate
        noiseClass
    end
    
    properties (Access = private)
        axesHandle
        nlAxesHandle
        lineHandle
        nlHandle
        stimulus1
        response1
        nonlinearityBins = 150
    end
    
    methods
        
        function obj = OrthoAnnulusNoiseFigure(device, varargin)
            ip = inputParser();
            ip.addParameter('recordingType', 'extracellular', @(x)ischar(x));
            ip.addParameter('noiseClass', 'gaussian', @(x)ischar(x));
            ip.addParameter('preTime',0.0, @(x)isfloat(x));
            ip.addParameter('stimTime',0.0, @(x)isfloat(x));
            ip.addParameter('frameRate',60.0, @(x)isfloat(x));
            
            ip.parse(varargin{:});
            
            obj.device = device;
            obj.recordingType = ip.Results.recordingType;
            obj.noiseClass = ip.Results.noiseClass;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            obj.frameRate = ip.Results.frameRate;
            
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
            obj.response1 = [];
            
            obj.setTitle([obj.device.name ': temporal filter']);
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t); 
        end
        
        function clear(obj)
            cla(obj.axesHandle);
            cla(obj.nlAxesHandle);
            obj.stimulus1 = [];
            obj.response1 = [];
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
                y = manookinlab.util.responseByType(quantities, obj.recordingType, obj.preTime, sampleRate);
                
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
                    y = manookinlab.util.binData(y(prePts+1:end), binRate, sampleRate);
                else
                    y = y(prePts+1:end);
                end
                
                % Make sure it's a row.
                y = y(:)';

                % Pull the seed.
                seed = epoch.parameters('seed');
                minRadius = epoch.parameters('minRadiusPix');
                maxRadius = epoch.parameters('maxRadiusPix');
                
                noiseStream = RandStream('mt19937ar', 'Seed', seed);
                
                %----------------------------------------------------------
                % Get the first frame sequence.
                numFrames = obj.stimTime*1e-3*obj.frameRate + 15;
                if strcmpi(obj.noiseClass, 'gaussian')
                    frameValues = 0.5*(0.3*noiseStream.randn(1, numFrames))+0.5;
                    frameValues(frameValues < 0) = 0; 
                    frameValues(frameValues > 1) = 1;
                    frameValues = (maxRadius-minRadius)*frameValues+minRadius;
                else
                    frameValues = (maxRadius-minRadius)*noiseStream.rand(1, numFrames)+minRadius;
                end
                % Subtract the mean.
                frameValues = frameValues - mean(frameValues(:));
                
                if binRate > obj.frameRate
                    n = round(binRate / obj.frameRate);
                    frameValues = ones(n,1)*frameValues(:)';
                    frameValues = frameValues(:);
                end
                fvals = zeros(size(y));
                fvals(1 : floor(obj.stimTime*1e-3*binRate)) = frameValues(1 : floor(obj.stimTime*1e-3*binRate));
                frameValues = fvals;
                
                % Make it the same size as the stim frames.
                y = y(1 : length(frameValues));
                
                % Zero out the first half-second while cell is adapting to
                % stimulus.
                y(1 : floor(binRate/2)) = 0;
                frameValues(1 : floor(binRate/2)) = 0;
                
                obj.stimulus1 = [obj.stimulus1; frameValues(:)'];
                obj.response1 = [obj.response1; y(:)'];
                
                % Reverse correlation.
                lf = real(ifft(mean((fft(obj.response1,[],2).*conj(fft(obj.stimulus1,[],2))),1)));
                lf = lf / norm(lf);
                
                % Calculate the linear prediction.
                prediction = zeros(size(obj.response1));
                for n = 1 : size(obj.stimulus1,1)
                    prediction(n,:) = real(ifft(fft(lf) .* fft(obj.stimulus1(n,:))));
                end
                prediction(isnan(prediction))=0;
                
                % Bin the nonlinearity
                [xBin1, yBin1] = manookinlab.util.binNonlinearity(prediction, obj.response1, obj.nonlinearityBins); 
                
                plotLngth = floor(binRate/2);
                
                % Plot the data.
                cla(obj.axesHandle);
                line((1:plotLngth)/binRate, lf(1:plotLngth),...
                    'Parent', obj.axesHandle, 'Color', 'k');
                axis(obj.axesHandle, 'tight');
                
                cla(obj.nlAxesHandle);
                line(xBin1, yBin1, ...
                    'Parent', obj.nlAxesHandle, 'Color', 'k', 'Marker', '.');
                axis(obj.nlAxesHandle, 'tight');
            end
        end  
    end
end