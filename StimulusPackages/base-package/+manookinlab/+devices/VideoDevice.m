classdef VideoDevice < symphonyui.core.Device
    properties (Access = private, Transient)
        stageClient
        microdisplay
    end
    
    methods
        function obj = VideoDevice(varargin)
            ip = inputParser();
            ip.addParameter('host', 'localhost', @ischar);
            ip.addParameter('port', 5678, @isnumeric);
            ip.addParameter('micronsPerPixel', @isnumeric);
            ip.addParameter('gammaRamps', containers.Map( ...
                {'red', 'green', 'blue'}, ...
                {linspace(0, 65535, 256), linspace(0, 65535, 256), linspace(0, 65535, 256)}), ...
                @(r)isa(r, 'containers.Map'));
            ip.parse(varargin{:});
            
            cobj = Symphony.Core.UnitConvertingExternalDevice(['SimulatedStage.Stage@' ip.Results.host], 'Unspecified', Symphony.Core.Measurement(0, symphonyui.core.Measurement.UNITLESS));
            obj@symphonyui.core.Device(cobj);
            obj.cobj.MeasurementConversionTarget = symphonyui.core.Measurement.UNITLESS;
            
            obj.stageClient = stage.core.network.StageClient();
            obj.stageClient.connect(ip.Results.host, ip.Results.port);
            canvasSize = obj.stageClient.getCanvasSize();
            
            obj.stageClient.setMonitorGamma(1);
            
            obj.stageClient.setMonitorGammaRamp(...
                ip.Results.gammaRamps('red'),...
                ip.Results.gammaRamps('green'), ...
                ip.Results.gammaRamps('blue'));
            
            obj.addConfigurationSetting('canvasSize', canvasSize, 'isReadOnly', true);
            obj.addConfigurationSetting('monitorRefreshRate', obj.stageClient.getMonitorRefreshRate(), 'isReadOnly', true);
            obj.addConfigurationSetting('centerOffset', [0 0], 'isReadOnly', true);
            obj.addConfigurationSetting('micronsPerPixel', ip.Results.micronsPerPixel, 'isReadOnly', true);
        end
        
        function close(obj)
            if ~isempty(obj.stageClient)
                obj.stageClient.disconnect();
            end
            if ~isempty(obj.microdisplay)
                obj.microdisplay.disconnect();
            end
        end
        
        function s = getCanvasSize(obj)
            s = obj.getConfigurationSetting('canvasSize');
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
        
        function play(obj, presentation, prerender)
            if nargin < 3
                prerender = false;
            end
            
            canvasSize = obj.getCanvasSize();
            
            background = stage.builtin.stimuli.Rectangle();
            background.size = canvasSize;
            background.position = canvasSize/2;
            background.color = presentation.backgroundColor;
            presentation.setBackgroundColor(0);
            presentation.insertStimulus(1, background);
            
            tracker = stage.builtin.stimuli.FrameTracker();
            tracker.size = [canvasSize(1) * 1/8, canvasSize(2)];
            tracker.position = [canvasSize(1) - (canvasSize(1)/16), canvasSize(2)/2];
            presentation.addStimulus(tracker);
            
            trackerColor = stage.builtin.controllers.PropertyController(tracker, 'color', @(s)mod(s.frame, 2) && double(s.time + (1/s.frameRate) < presentation.duration));
            presentation.addController(trackerColor); 
            
            if prerender
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
        
        function p = um2pix(obj, um)
            micronsPerPixel = obj.getConfigurationSetting('micronsPerPixel');
            p = round(um / micronsPerPixel);
        end
    end
end