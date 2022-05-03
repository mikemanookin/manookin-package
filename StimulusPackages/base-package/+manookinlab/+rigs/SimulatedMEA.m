classdef SimulatedMEA < symphonyui.core.descriptions.RigDescription
    
    methods
        
        function obj = SimulatedMEA()
            import symphonyui.builtin.daqs.*;
            import symphonyui.builtin.devices.*;
            import symphonyui.core.*;
            
            daq = HekaSimulationDaqController();
            obj.daqController = daq;
            
            % Rig name and laboratory.
            rigDev = manookinlab.devices.RigPropertyDevice('ManookinLab','SimulatedMEA');
            obj.addDevice(rigDev);
            
            amp1 = MultiClampDevice('Amp1', 1).bindStream(daq.getStream('ao0')).bindStream(daq.getStream('ai0'));
            obj.addDevice(amp1);
            
%             % Get calibration resources.
%             ramps = containers.Map();
%             ramps('red')    = 65535 * importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'red_gamma_ramp.txt'));
%             ramps('green')  = 65535 * importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'green_gamma_ramp.txt'));
%             ramps('blue')   = 65535 * importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'blue_gamma_ramp.txt'));
            
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
            
            microdisplay = manookinlab.devices.VideoDevice('micronsPerPixel', 0.8);
            microdisplay.addResource('quantalCatch', containers.Map( ...
                {'10xND00','10xND05','10xND10','10xND20','10xND30','10xND40','60xND00','60xND05','60xND10','60xND20','60xND30','60xND40'}, {...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'LCR10xND00.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'LCR10xND05.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'LCR10xND10.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'LCR10xND20.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'LCR10xND30.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'LCR10xND40.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'LCR60xND00.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'LCR60xND05.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'LCR60xND10.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'LCR60xND20.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'LCR60xND30.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'LCR60xND40.txt')), ...
                }));
            obj.addDevice(microdisplay);
            
            % Add the filter wheel.
            filterWheel = manookinlab.devices.FilterWheelDevice('comPort', 'COM13');
            obj.addDevice(filterWheel);
            
            % Add a device for external triggering to synchronize MEA DAQ clock with Symphony DAQ clock.
            trigger = riekelab.devices.TriggerDevice();
            trigger.bindStream(daq.getStream('doport1'));
            daq.getStream('doport1').setBitPosition(trigger, 1);
            obj.addDevice(trigger);
            
            mea = manookinlab.devices.MEADevice(9001);
%             mea = manookinlab.devices.MEADevice('host', 'localhost');
            obj.addDevice(mea);
        end
    end
    
end

