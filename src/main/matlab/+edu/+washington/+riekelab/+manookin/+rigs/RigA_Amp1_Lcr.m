classdef RigA_Amp1_Lcr < edu.washington.riekelab.manookin.rigs.RigA
    methods
        function obj = RigA_Amp1_Lcr()
            import symphonyui.builtin.daqs.*;
            import symphonyui.builtin.devices.*;
            import symphonyui.core.*;
            
            daq = obj.daqController;
            
            % Add the amplifier
            amp1 = MultiClampDevice('Amp1', 1).bindStream(daq.getStream('ao0')).bindStream(daq.getStream('ai0'));
            obj.addDevice(amp1);
            
            % Add the LightCrafter
            lightCrafter = edu.washington.riekelab.devices.LightCrafterDevice('micronsPerPixel', 0.1121);
            
            % Binding the lightCrafter to an unused stream only so its configuration settings are written to each epoch.
            daq = obj.daqController;
            lightCrafter.bindStream(daq.getStream('doport1'));
            daq.getStream('doport1').setBitPosition(lightCrafter, 15);
            
            % Add the LED spectra.
            lightCrafter.addResource('spectrum', containers.Map( ...
                {'red', 'Green_505nm', 'Green_570nm', 'blue', 'wavelength'}, { ...
                importdata(edu.washington.riekelab.manookin.Package.getCalibrationResource('rigs', 'rig_A', 'red_spectrum.txt')), ...
                importdata(edu.washington.riekelab.manookin.Package.getCalibrationResource('rigs', 'rig_A', 'Green_505nm_spectrum.txt')), ...
                importdata(edu.washington.riekelab.manookin.Package.getCalibrationResource('rigs', 'rig_A', 'Green_570nm_spectrum.txt')), ...
                importdata(edu.washington.riekelab.manookin.Package.getCalibrationResource('rigs', 'rig_A', 'blue_spectrum.txt')), ...
                importdata(edu.washington.riekelab.manookin.Package.getCalibrationResource('rigs', 'rig_A', 'wavelength.txt'))}));
            
            obj.addDevice(lightCrafter);
            
            % Add the frame syncs
            frameMonitor = UnitConvertingDevice('Frame Sync', 'V').bindStream(obj.daqController.getStream('ai3'));
            obj.addDevice(frameMonitor);
        end
    end
end