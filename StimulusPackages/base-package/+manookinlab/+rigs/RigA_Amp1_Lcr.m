classdef RigA_Amp1_Lcr < manookinlab.rigs.RigA
    methods
        function obj = RigA_Amp1_Lcr()
            import symphonyui.builtin.daqs.*;
            import symphonyui.builtin.devices.*;
            import symphonyui.core.*;
            
            daq = obj.daqController;
            
            % Rig name and laboratory.
            rigDev = manookinlab.devices.RigPropertyDevice('ManookinLab','ManookinA');
            obj.addDevice(rigDev);
            
            % Add the amplifier
            amp1 = MultiClampDevice('Amp1', 1).bindStream(daq.getStream('ao0')).bindStream(daq.getStream('ai0'));
            obj.addDevice(amp1);
            
            % Add the LightCrafter
            lightCrafter = edu.washington.riekelab.devices.LightCrafterDevice('micronsPerPixel', 1);
            
            % Binding the lightCrafter to an unused stream only so its configuration settings are written to each epoch.
            daq = obj.daqController;
            lightCrafter.bindStream(daq.getStream('doport1'));
            daq.getStream('doport1').setBitPosition(lightCrafter, 15);
            
            % Add the LED spectra.
            lightCrafter.addResource('spectrum', containers.Map( ...
                {'red', 'Green_505nm', 'Green_570nm', 'blue', 'wavelength'}, { ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'red_spectrum.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'Green_505nm_spectrum.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'Green_570nm_spectrum.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'blue_spectrum.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'wavelength.txt'))}));
            
            % Add the quantal catch measurements.
            lightCrafter.addResource('quantalCatch', containers.Map( ...
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
            
            
            obj.addDevice(lightCrafter);
            
            % Add the frame syncs
            frameMonitor = UnitConvertingDevice('Frame Sync', 'V').bindStream(obj.daqController.getStream('ai3'));
            obj.addDevice(frameMonitor);
        end
    end
end