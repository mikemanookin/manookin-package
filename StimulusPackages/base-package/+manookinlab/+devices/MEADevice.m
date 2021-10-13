classdef MEADevice < symphonyui.core.Device
    properties (Access = private, Transient)
        client
    end
    
    methods
        function obj = MEADevice(varargin)
            ip = inputParser();
            ip.addParameter('host', '192.168.1.1', @ischar);
            ip.addParameter('port', 9876, @isnumeric);
            ip.parse(varargin{:});
            
            cobj = Symphony.Core.UnitConvertingExternalDevice(['MEA@' ip.Results.host], 'Unspecified', Symphony.Core.Measurement(0, symphonyui.core.Measurement.UNITLESS));
            obj@symphonyui.core.Device(cobj);
            obj.cobj.MeasurementConversionTarget = symphonyui.core.Measurement.UNITLESS;
            
            % Start the client
            obj.start();
            
            % Connect to the host server.
            obj.connect(ip.Results.host, ip.Results.port);
            
%             obj.meaServer.start();
%             obj.meaServer.connect(ip.Results.host, ip.Results.port);
%             canvasSize = obj.meaServer.getCanvasSize();
%             
%             obj.addConfigurationSetting('canvasSize', canvasSize, 'isReadOnly', true);
%             obj.addConfigurationSetting('monitorRefreshRate', obj.meaServer.getMonitorRefreshRate(), 'isReadOnly', true);
%             obj.addConfigurationSetting('centerOffset', [0 0], 'isReadOnly', true);
%             obj.addConfigurationSetting('micronsPerPixel', ip.Results.micronsPerPixel, 'isReadOnly', true);
        end
        
        function start(obj)
            obj.client = manookinlab.network.MEAClient();
        end
        
        function connect(obj, host, port)
            obj.client.connect(host, port)
        end
        
        function close(obj)
            if ~isempty(obj.client)
                obj.client.close();
            end
        end
        
        function fname = getFileName(obj, timeout)
            if isempty('timeout','var')
                timeout = 30; % 30 second timeout by default.
            end
            fname = obj.client.getFileName(timeout);
        end
        
        function s = getCanvasSize(obj)
            s = obj.getConfigurationSetting('canvasSize');
        end
        
        function setCenterOffset(obj, o)
            delta = o - obj.getCenterOffset();
            obj.meaServer.setCanvasProjectionTranslate(delta(1), delta(2), 0);
            obj.setReadOnlyConfigurationSetting('centerOffset', [o(1) o(2)]);
        end
        
        function o = getCenterOffset(obj)
            o = obj.getConfigurationSetting('centerOffset');
        end
        
        function r = getMonitorRefreshRate(obj)
            r = obj.getConfigurationSetting('monitorRefreshRate');
        end
        
        
    end
end