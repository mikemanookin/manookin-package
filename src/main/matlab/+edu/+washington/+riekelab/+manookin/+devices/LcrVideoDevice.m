classdef LcrVideoDevice < symphonyui.core.Device
    
    properties (Access = private, Transient)
        stageClient
        lightCrafter
        patternRatesToAttributes
    end
    
    methods
        
        function obj = LcrVideoDevice(varargin)
            ip = inputParser();
            ip.addParameter('host', 'localhost', @ischar);
            ip.addParameter('port', 5678, @isnumeric);
            ip.addParameter('micronsPerPixel', @isnumeric);
            ip.addParameter('gammaRamps', containers.Map( ...
                {'red', 'green', 'blue'}, ...
                {linspace(0, 65535, 256), linspace(0, 65535, 256), linspace(0, 65535, 256)}), ...
                @(r)isa(r, 'containers.Map'));
            ip.parse(varargin{:});
            
            cobj = Symphony.Core.UnitConvertingExternalDevice(['LcrVideo Stage@' ip.Results.host], 'Texas Instruments', Symphony.Core.Measurement(0, symphonyui.core.Measurement.UNITLESS));
            obj@symphonyui.core.Device(cobj);
            obj.cobj.MeasurementConversionTarget = symphonyui.core.Measurement.UNITLESS;
            
            obj.stageClient = stage.core.network.StageClient();
            obj.stageClient.connect(ip.Results.host, ip.Results.port);
            obj.stageClient.setMonitorGamma(1);
            
            obj.stageClient.setMonitorGammaRamp(...
                ip.Results.gammaRamps('red'),...
                ip.Results.gammaRamps('green'), ...
                ip.Results.gammaRamps('blue'));
            
            trueCanvasSize = obj.stageClient.getCanvasSize();
            canvasSize = [trueCanvasSize(1) * 2, trueCanvasSize(2)];
            
            obj.stageClient.setCanvasProjectionIdentity();
            obj.stageClient.setCanvasProjectionOrthographic(0, canvasSize(1), 0, canvasSize(2));
            
            obj.lightCrafter = LightCrafter4500(obj.stageClient.getMonitorRefreshRate());
            obj.lightCrafter.connect();
            obj.lightCrafter.setMode('video');
            obj.lightCrafter.setLedEnables(true, false, false, false);
            [auto, red, green, blue] = obj.lightCrafter.getLedEnables();
            
            refreshRate = obj.stageClient.getMonitorRefreshRate();
            
            obj.addConfigurationSetting('canvasSize', canvasSize, 'isReadOnly', true);
            obj.addConfigurationSetting('trueCanvasSize', trueCanvasSize, 'isReadOnly', true);
            obj.addConfigurationSetting('monitorRefreshRate', refreshRate, 'isReadOnly', true);
            obj.addConfigurationSetting('prerender', false, 'isReadOnly', true);
            obj.addConfigurationSetting('lightCrafterLedEnables',  [auto, red, green, blue], 'isReadOnly', true);
            obj.addConfigurationSetting('micronsPerPixel', ip.Results.micronsPerPixel, 'isReadOnly', true);
            obj.addResource('gammaRamps', ip.Results.gammaRamps);
        end
        
        function close(obj)
            try %#ok<TRYNC>
                obj.stageClient.resetCanvasProjection();
            end
            if ~isempty(obj.stageClient)
                obj.stageClient.disconnect();
            end
            if ~isempty(obj.lightCrafter)
                obj.lightCrafter.disconnect();
            end
        end
        
        function s = getCanvasSize(obj)
            s = obj.getConfigurationSetting('canvasSize');
        end
        
        function s = getTrueCanvasSize(obj)
            s = obj.getConfigurationSetting('trueCanvasSize');
        end
        
        function r = getMonitorRefreshRate(obj)
            r = obj.getConfigurationSetting('monitorRefreshRate');
        end
        
        function setMonitorGammaRamp(obj, r, g, b)
            obj.stageClient.setMonitorGammaRamp(r, g, b);
        end
        
        function setPrerender(obj, tf)
            obj.setReadOnlyConfigurationSetting('prerender', logical(tf));
        end
        
        function tf = getPrerender(obj)
            tf = obj.getConfigurationSetting('prerender');
        end
        
        function play(obj, presentation)
            canvasSize = obj.getCanvasSize();
            
            background = stage.builtin.stimuli.Rectangle();
            background.size = canvasSize;
            background.position = canvasSize/2;
            background.color = presentation.backgroundColor;
            presentation.setBackgroundColor(0);
            presentation.insertStimulus(1, background);
            
            tracker = stage.builtin.stimuli.Rectangle();
            tracker.size = [canvasSize(1) * 1/8, canvasSize(2)];
            tracker.position = [canvasSize(1) - (canvasSize(1)/16), canvasSize(2)/2];
            presentation.addStimulus(tracker);
            
            trackerColor = stage.builtin.controllers.PropertyController(tracker, 'color', @(s)mod(s.frame, 2) && double(s.time + (1/s.frameRate) < presentation.duration));
            presentation.addController(trackerColor);            
            
            if obj.getPrerender()
                player = stage.builtin.players.PrerenderedPlayer(presentation);
            else
                player = stage.builtin.players.RealtimePlayer(presentation);
            end
            obj.stageClient.play(player);
        end
        
        function replay(obj)
            obj.stageClient.replay();
        end
        
        function i = getPlayInfo(obj)
            i = obj.stageClient.getPlayInfo();
        end
        
        function clearMemory(obj)
           obj.stageClient.clearMemory();
        end
        
        function setLedEnables(obj, auto, red, green, blue)
            obj.lightCrafter.setLedEnables(auto, red, green, blue);
            [a, r, g, b] = obj.lightCrafter.getLedEnables();
            obj.setReadOnlyConfigurationSetting('lightCrafterLedEnables', [a, r, g, b]);
        end
        
        function [auto, red, green, blue] = getLedEnables(obj)
            [auto, red, green, blue] = obj.lightCrafter.getLedEnables();
        end
        
        function r = availablePatternRates(obj)
            r = obj.patternRatesToAttributes.keys;
        end
        
        function setPatternRate(obj, rate)
            if ~obj.patternRatesToAttributes.isKey(rate)
                error([num2str(rate) ' is not an available pattern rate']);
            end
            attributes = obj.patternRatesToAttributes(rate);
            obj.lightCrafter.setPatternAttributes(attributes{:});
            obj.setReadOnlyConfigurationSetting('lightCrafterPatternRate', obj.lightCrafter.currentPatternRate());
            
            renderer = stage.builtin.renderers.PatternRenderer(attributes{3}, attributes{1});
            obj.stageClient.setCanvasRenderer(renderer);
        end
        
        function r = getPatternRate(obj)
            r = obj.lightCrafter.currentPatternRate();
        end
        
        function p = um2pix(obj, um)
            micronsPerPixel = obj.getConfigurationSetting('micronsPerPixel');
            p = round(um / micronsPerPixel);
        end
        
        function inverse = getGammaRampFromFunction(obj) %#ok<MANU>
            modelfun = @(p,x)(p(1)*normcdf(x, p(2), p(3)));

            xaxis = (0:255)/255;
            
            % <=0.7: p=[1.3957 0.7449 0.2650]
            y2 = modelfun([1.3957 0.7449 0.2650],xaxis);

            y2(180:end) = modelfun([1.0188 0.6569 0.1763], xaxis(180:end));
            
            inverse = zeros(1,256);

            for k = 2 : 256
                % Take the difference.
                d = abs(y2 - xaxis(k));
                v = find(d == min(d), 1);
                inverse(k) = xaxis(v);
            end
            inverse = 65535*inverse;
        end
        
    end
    
end

