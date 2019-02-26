classdef RigA < symphonyui.core.descriptions.RigDescription
    
    methods
        function obj = RigA()
            import symphonyui.builtin.daqs.*;
            import symphonyui.builtin.devices.*;
            import symphonyui.core.*;
            
            daq = HekaDaqController();
            obj.daqController = daq;
            
            % Add the frame syncs
            fMonitor = UnitConvertingDevice('White Sync', 'V').bindStream(daq.getStream('ai6'));
            obj.addDevice(fMonitor);
            
            % Add the green and blue LEDs
%             green = UnitConvertingDevice('Green LED', 'V').bindStream(daq.getStream('ao2'));
%             obj.addDevice(green);
%             
%             blue = UnitConvertingDevice('Blue LED', 'V').bindStream(daq.getStream('ao3'));
%             obj.addDevice(blue);
            
%             red = UnitConvertingDevice('Red LED', 'V').bindStream(daq.getStream('ao1'));
%             red.addConfigurationSetting('ndfs', {}, ...
%                 'type', PropertyType('cellstr', 'row', {'B1', 'B2', 'B3', 'B4', 'B5', 'B11'}));
%             red.addResource('ndfAttenuations', containers.Map( ...
%                 {'B1', 'B2', 'B3', 'B4', 'B5', 'B11'}, ...
%                 {0.29, 0.61, 1.01, 2.08, 4.41, 3.94}));
%             red.addConfigurationSetting('gain', '', ...
%                 'type', PropertyType('char', 'row', {'', 'low', 'medium', 'high'}));
%             red.addResource('fluxFactorPaths', containers.Map( ...
%                 {'low', 'medium', 'high'}, { ...
%                 riekelab.Package.getCalibrationResource('rigs', 'two_photon', 'red_led_low_flux_factors.txt'), ...
%                 riekelab.Package.getCalibrationResource('rigs', 'two_photon', 'red_led_medium_flux_factors.txt'), ...
%                 riekelab.Package.getCalibrationResource('rigs', 'two_photon', 'red_led_high_flux_factors.txt')}));
%             red.addConfigurationSetting('lightPath', '', ...
%                 'type', PropertyType('char', 'row', {'', 'below', 'above'}));
%             red.addResource('spectrum', importdata(riekelab.Package.getCalibrationResource('rigs', 'two_photon', 'red_led_spectrum.txt')));
%             obj.addDevice(red);
            
            temperature = UnitConvertingDevice('Temperature Controller', 'V', 'manufacturer', 'Warner Instruments').bindStream(daq.getStream('ai7'));
            obj.addDevice(temperature);
            
            % Add the frame monitor
            frameMonitor = UnitConvertingDevice('Frame Monitor', 'V').bindStream(obj.daqController.getStream('ai2'));
            obj.addDevice(frameMonitor);
            
            trigger = UnitConvertingDevice('Oscilloscope Trigger', symphonyui.core.Measurement.UNITLESS).bindStream(daq.getStream('doport1'));
            daq.getStream('doport1').setBitPosition(trigger, 0);
            obj.addDevice(trigger);
            
            % Add the filter wheel.
            filterWheel = manookinlab.devices.FilterWheelDevice('comPort', 'COM3');
            
            % Binding the filter wheel to an unused stream only so its configuration settings are written to each epoch.
            filterWheel.bindStream(daq.getStream('doport1'));
            daq.getStream('doport1').setBitPosition(filterWheel, 14);
            obj.addDevice(filterWheel);
            
            % SciScan Trigger.
%             trigger2 = UnitConvertingDevice('SciScan Trigger', symphonyui.core.Measurement.UNITLESS).bindStream(daq.getStream('doport1'));
%             daq.getStream('doport1').setBitPosition(trigger2, 1);
%             obj.addDevice(trigger2);
        end
    end
    
end