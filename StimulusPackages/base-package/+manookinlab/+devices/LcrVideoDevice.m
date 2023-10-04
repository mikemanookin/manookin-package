classdef LcrVideoDevice < symphonyui.core.Device
    
    properties (Access = private, Transient)
        stageClient
        lightCrafter
        patternRatesToAttributes
    end
    
    properties (Access = private)
        max_led_current
    end
    
    methods
        
        function obj = LcrVideoDevice(varargin)
            ip = inputParser();
            ip.addParameter('host', 'localhost', @ischar);
            ip.addParameter('port', 5678, @isnumeric);
            ip.addParameter('micronsPerPixel', @isnumeric);
            ip.addParameter('ledCurrents',[], @isnumeric);
            ip.addParameter('customLightEngine', false, @islogical);
            ip.addParameter('local_movie_directory','C:\Users\Public\Documents\GitRepos\Symphony2\movies\', @ischar);
            ip.addParameter('stage_movie_directory','C:\Users\Public\Documents\GitRepos\Symphony2\movies\', @ischar);
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
            
            if ip.Results.customLightEngine
                obj.max_led_current = 100;
            else
                obj.max_led_current = 200;
            end
            if ~isempty(ip.Results.ledCurrents)
                led_currents = ip.Results.ledCurrents;
                obj.lightCrafter.setLedCurrents(min(led_currents(1),obj.max_led_current), min(led_currents(2),obj.max_led_current), min(led_currents(3),obj.max_led_current));
            end
            % Get the LED currents.
            [red_current, green_current, blue_current] = obj.lightCrafter.getLedCurrents();
            
            refreshRate = obj.stageClient.getMonitorRefreshRate();
            
            obj.addConfigurationSetting('local_movie_directory', ip.Results.local_movie_directory, 'isReadOnly', true);
            obj.addConfigurationSetting('stage_movie_directory', ip.Results.stage_movie_directory, 'isReadOnly', true);
            obj.addConfigurationSetting('canvasSize', canvasSize, 'isReadOnly', true);
            obj.addConfigurationSetting('trueCanvasSize', trueCanvasSize, 'isReadOnly', true);
            obj.addConfigurationSetting('lightCrafterLedCurrents',[red_current, green_current, blue_current],'isReadOnly',true);
            obj.addConfigurationSetting('centerOffset', [0 0], 'isReadOnly', true);
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
        
        function setCenterOffset(obj, o)
            delta = o - obj.getCenterOffset();
            obj.stageClient.setCanvasProjectionTranslate(delta(1), delta(2), 0);
            obj.setReadOnlyConfigurationSetting('centerOffset', [o(1) o(2)]);
        end
        
        function o = getCenterOffset(obj)
            o = obj.getConfigurationSetting('centerOffset');
        end
        
        function r = getMonitorRefreshRate(obj)
            r = obj.getConfigurationSetting('monitorRefreshRate');
        end
        
        function [r, g, b] = getMonitorGammaRamp(obj)
            [r, g, b] = obj.stageClient.getMonitorGammaRamp();
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
            centerOffset = obj.getCenterOffset();
            
            background = stage.builtin.stimuli.Rectangle();
            background.size = canvasSize;
            background.position = canvasSize/2 - centerOffset;
            background.color = presentation.backgroundColor;
            presentation.setBackgroundColor(0);
            presentation.insertStimulus(1, background);
            
            tracker = stage.builtin.stimuli.Rectangle();
            tracker.size = [canvasSize(1) * 1/8, canvasSize(2)];
            tracker.position = [canvasSize(1) - (canvasSize(1)/16), canvasSize(2)/2] - centerOffset;
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
        end
        
        function [auto, red, green, blue] = getLedEnables(obj)
            [auto, red, green, blue] = obj.lightCrafter.getLedEnables();
        end
        
        function [red, green, blue] = getLedCurrents(obj)
            [red, green, blue] = obj.lightCrafter.getLedCurrents();
        end

        function setLedCurrents(obj, red, green, blue)
            red = min(red, obj.max_led_current);
            green = min(green, obj.max_led_current);
            blue = min(blue,obj.max_led_current);
            obj.lightCrafter.setLedCurrents(red, green, blue);
            obj.setReadOnlyConfigurationSetting('lightCrafterLedCurrents', [red, green, blue]);
        end
        
        function r = availablePatternRates(obj)
            r = {'60'};
        end
        
        function setPatternRate(obj, rate)
        end
        
        function r = getPatternRate(obj)
            r = [];
        end
        
        function p = um2pix(obj, um)
            micronsPerPixel = obj.getConfigurationSetting('micronsPerPixel');
            p = round(um / micronsPerPixel);
        end
        
        function u = pix2um(obj, pix)
            micronsPerPixel = obj.getConfigurationSetting('micronsPerPixel');
            u = pix * micronsPerPixel;
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

