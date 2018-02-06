classdef LCR_RGB < symphonyui.core.descriptions.RigDescription
    
    methods
        
        function obj = LCR_RGB()
            import symphonyui.builtin.daqs.*;
            import symphonyui.builtin.devices.*;
            import symphonyui.core.*;
            
            daq = HekaSimulationDaqController();
            obj.daqController = daq;
            
            amp1 = MultiClampDevice('Amp1', 1).bindStream(daq.getStream('ai0')).bindStream(daq.getStream('ai0'));
            obj.addDevice(amp1);
            
            green = UnitConvertingDevice('Green LED', 'V').bindStream(daq.getStream('ao2'));
            green.addConfigurationSetting('ndfs', {}, ...
                'type', PropertyType('cellstr', 'row', {'0.3', '0.6', '1.2', '3.0', '4.0'}));
            green.addConfigurationSetting('gain', '', ...
                'type', PropertyType('char', 'row', {'', 'low', 'medium', 'high'}));
            obj.addDevice(green);
            
            blue = UnitConvertingDevice('Blue LED', 'V').bindStream(daq.getStream('ao3'));
            blue.addConfigurationSetting('ndfs', {}, ...
                'type', PropertyType('cellstr', 'row', {'0.3', '0.6', '1.2', '3.0', '4.0'}));
            blue.addConfigurationSetting('gain', '', ...
                'type', PropertyType('char', 'row', {'', 'low', 'medium', 'high'}));
            obj.addDevice(blue);
            
             trigger1 = UnitConvertingDevice('Trigger1', symphonyui.core.Measurement.UNITLESS).bindStream(daq.getStream('doport1'));
            daq.getStream('doport1').setBitPosition(trigger1, 0);
            obj.addDevice(trigger1);
            
            trigger2 = UnitConvertingDevice('Trigger2', symphonyui.core.Measurement.UNITLESS).bindStream(daq.getStream('doport1'));
            daq.getStream('doport1').setBitPosition(trigger2, 2);
            obj.addDevice(trigger2);
            
            frameMonitor = UnitConvertingDevice('Frame Monitor', 'V').bindStream(obj.daqController.getStream('ai7'));
            obj.addDevice(frameMonitor);
            
            lightcrafter = edu.washington.riekelab.manookin.devices.LightCrafterRGBDevice('micronsPerPixel', 0.6727);
            obj.addDevice(lightcrafter);
            
            % Add the filter wheel.
            filterWheel = edu.washington.riekelab.manookin.devices.FilterWheelDevice('comPort', 'COM13');
            
            % Binding the filter wheel to an unused stream only so its configuration settings are written to each epoch.
            daq = obj.daqController;
            filterWheel.bindStream(daq.getStream('doport1'));
            daq.getStream('doport1').setBitPosition(filterWheel, 15);
            
            obj.addDevice(filterWheel);
        end
    end
    
end

