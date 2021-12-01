classdef MEADevice < symphonyui.core.Device
    properties (Access = private, Transient)
        client
    end
    
    methods
        function obj = MEADevice(varargin)
            ip = inputParser();
            ip.addParameter('host', 'localhost', @ischar);
            ip.addParameter('port', 9876, @isnumeric);
            ip.parse(varargin{:});
            
            cobj = Symphony.Core.UnitConvertingExternalDevice(['MEA@' ip.Results.host], 'Unspecified', Symphony.Core.Measurement(0, symphonyui.core.Measurement.UNITLESS));
            obj@symphonyui.core.Device(cobj);
            obj.cobj.MeasurementConversionTarget = symphonyui.core.Measurement.UNITLESS;
            
            % Start the client
            obj.start();
            
            % Connect to the host server.
            obj.connect(ip.Results.host, ip.Results.port);
            
        end
        
        function start(obj)
            obj.client = manookinlab.network.MEAClient();
        end
        
        function connect(obj, host, port)
            % Check if this is the local host.
            if strcmpi(host, 'localhost')
                host = java.net.InetAddress.getLocalHost();
            end
            obj.client.connect(host, port)
        end
        
        function close(obj)
            if ~isempty(obj.client)
                obj.client.close();
            end
        end
        
        function fname = getFileName(obj, timeout)
            if ~exist('timeout','var')
                timeout = 30; % 30 second timeout by default.
            end
            fname = obj.client.getFileName(timeout);
        end
        
        
    end
end