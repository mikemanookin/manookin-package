classdef RigA_Amp2_Video < manookinlab.rigs.RigA
    methods
        function obj = RigA_Amp2_Video()
            import symphonyui.builtin.daqs.*;
            import symphonyui.builtin.devices.*;
            import symphonyui.core.*;
            
            daq = obj.daqController;
            
            % Rig name and laboratory.
            rigDev = manookinlab.devices.RigPropertyDevice('ManookinLab','ManookinA');
            obj.addDevice(rigDev);
            
            % Add the amplifier
            amp2 = MultiClampDevice('Amp2', 1).bindStream(daq.getStream('ao1')).bindStream(daq.getStream('ai1'));
            obj.addDevice(amp2);
            
            % Get calibration resources.
            ramps = containers.Map();
            ramps('red')    = 65535 * importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'red_gamma_ramp.txt'));
            ramps('green')  = 65535 * importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'green_gamma_ramp.txt'));
            ramps('blue')   = 65535 * importdata(manookinlab.Package.getCalibrationResource('rigs', 'rig_A', 'blue_gamma_ramp.txt'));
            
            % Add the LightCrafter
            lightCrafter = manookinlab.devices.LcrVideoDevice(...
                'micronsPerPixel', 1, ...
                'gammaRamps',ramps);
            
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
            
            obj.addDevice(lightCrafter);
            
            % Add the red syncs (240 Hz)
            frameMonitor = UnitConvertingDevice('Red Sync', 'V').bindStream(obj.daqController.getStream('ai4'));
            obj.addDevice(frameMonitor);
        end
    end
end