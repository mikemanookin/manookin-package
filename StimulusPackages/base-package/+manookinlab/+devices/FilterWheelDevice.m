classdef FilterWheelDevice < symphonyui.core.Device
    
    properties (Access = private)
        wheelPosition
        ndf
    end
    
    
    properties (Access = private)
        filterWheel
        ndfValues = [0 0.5 1.0 2.0 3.0 4.0];
        isOpen
    end
    
    methods
        function obj = FilterWheelDevice(varargin)
            
            ip = inputParser();
            ip.addParameter('comPort', 'COM13', @ischar);
            ip.addParameter('NDF', 4.0, @isnumeric);
            ip.addParameter('objectiveMag', 60, @isnumeric);
            ip.addParameter('greenLEDName', '505nm', @ischar);
            ip.parse(varargin{:});
            
            cobj = Symphony.Core.UnitConvertingExternalDevice('FilterWheel', 'ThorLabs', Symphony.Core.Measurement(0, symphonyui.core.Measurement.UNITLESS));
            obj@symphonyui.core.Device(cobj);
            obj.cobj.MeasurementConversionTarget = symphonyui.core.Measurement.UNITLESS;
            
            obj.addConfigurationSetting('NDF', 4.0);
            obj.addConfigurationSetting('objectiveMag', ip.Results.objectiveMag);
            obj.addConfigurationSetting('micronsPerPixel', 0.1121);
            obj.addConfigurationSetting('greenLEDName',ip.Results.greenLEDName);
            
            % Add configuration settings for the quantal catch.
            obj.addConfigurationSetting('Red_L', 0.0);
            obj.addConfigurationSetting('Red_M', 0.0);
            obj.addConfigurationSetting('Red_S', 0.0);
            obj.addConfigurationSetting('Red_rod', 0.0);
            obj.addConfigurationSetting('Green_L', 0.0);
            obj.addConfigurationSetting('Green_M', 0.0);
            obj.addConfigurationSetting('Green_S', 0.0);
            obj.addConfigurationSetting('Green_rod', 0.0);
            obj.addConfigurationSetting('Blue_L', 0.0);
            obj.addConfigurationSetting('Blue_M', 0.0);
            obj.addConfigurationSetting('Blue_S', 0.0);
            obj.addConfigurationSetting('Blue_rod', 0.0);
            
            % Try to connect.
            obj.connect(ip.Results.comPort);
            
            if obj.isOpen
                obj.setNDF(ip.Results.NDF);
                obj.ndf = 4;
            end
        end
        
        function connect(obj, comPort)
            try 
                obj.filterWheel = serial(comPort, 'BaudRate', 115200, 'DataBits', 8, 'StopBits', 1, 'Terminator', 'CR');
                fopen(obj.filterWheel);
                obj.isOpen = true;
            catch
                obj.isOpen = false;
            end
        end
        
        function close(obj)
            if obj.isOpen
                fclose(obj.filterWheel);
                obj.isOpen = false;
            end
        end
        
        function moveWheel(obj, position)
            fprintf(obj.filterWheel, ['pos=', num2str(position), '\n']);
            obj.wheelPosition = position;
        end
        
        function setNDF(obj, nd)
            try
                obj.moveWheel(find(obj.ndfValues == nd, 1));
                obj.setReadOnlyConfigurationSetting('NDF', nd);
            catch e
                disp(e.message);
            end
        end
        
        function nd = getNDF(obj)
            nd = obj.getConfigurationSetting('NDF');
        end
        
        function nm = getGreenLEDName(obj)
            nm = obj.getConfigurationSetting('greenLEDName');
        end
        
        function setGreenLEDName(obj, nm)
            obj.setReadOnlyConfigurationSetting('greenLEDName', nm);
        end
        
        function setObjective(obj, mag)
            obj.setReadOnlyConfigurationSetting('objectiveMag', mag);
            
            % Set microns per pixel.
            switch mag
                case 60
                    m = 0.1333;
                case 10 
                    m = 0.8;
                case 4
                    m = 2.0;
            end
            obj.setMicronsPerPixel(m);
        end
        
        function mag = getObjective(obj)
            mag = obj.getConfigurationSetting('objectiveMag');
        end
        
        function setQuantalCatch(obj, quantalCatch)
            % Set the quantal catch values.
            obj.setReadOnlyConfigurationSetting('Red_L', quantalCatch(1,1));
            obj.setReadOnlyConfigurationSetting('Red_M', quantalCatch(1,2));
            obj.setReadOnlyConfigurationSetting('Red_S', quantalCatch(1,3));
            obj.setReadOnlyConfigurationSetting('Red_rod', quantalCatch(1,4));
            obj.setReadOnlyConfigurationSetting('Green_L', quantalCatch(2,1));
            obj.setReadOnlyConfigurationSetting('Green_M', quantalCatch(2,2));
            obj.setReadOnlyConfigurationSetting('Green_S', quantalCatch(2,3));
            obj.setReadOnlyConfigurationSetting('Green_rod', quantalCatch(2,4));
            obj.setReadOnlyConfigurationSetting('Blue_L', quantalCatch(3,1));
            obj.setReadOnlyConfigurationSetting('Blue_M', quantalCatch(3,2));
            obj.setReadOnlyConfigurationSetting('Blue_S', quantalCatch(3,3));
            obj.setReadOnlyConfigurationSetting('Blue_rod', quantalCatch(3,4));
        end
        
        function setMicronsPerPixel(obj, m)
            obj.setReadOnlyConfigurationSetting('micronsPerPixel', m);
        end
        
        function m = getMicronsPerPixel(obj)
            m = obj.getConfigurationSetting('micronsPerPixel');
        end
        
        function position = getCurrentPosition(obj)
            if obj.isOpen
                fprintf(obj.filterWheel, 'pos=?\n');
                position = fscanf(obj.filterWheel);
            end
        end
    end
end