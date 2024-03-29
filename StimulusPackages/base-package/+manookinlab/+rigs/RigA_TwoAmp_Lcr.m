classdef RigA_TwoAmp_Lcr < manookinlab.rigs.RigA
    methods
        function obj = RigA_TwoAmp_Lcr()
             import symphonyui.builtin.daqs.*;
            import symphonyui.builtin.devices.*;
            import symphonyui.core.*;
            daq = obj.daqController;
            
            % Rig name and laboratory.
            rigDev = manookinlab.devices.RigPropertyDevice('ManookinLab','ManookinA');
            obj.addDevice(rigDev);

            % Add the amplifiers
            amp1 = MultiClampDevice('Amp1', 1).bindStream(daq.getStream('ao0')).bindStream(daq.getStream('ai0'));
            obj.addDevice(amp1);
            
            amp2 = MultiClampDevice('Amp2', 1).bindStream(daq.getStream('ao1')).bindStream(daq.getStream('ai1'));
            obj.addDevice(amp2);
            
            % Add the LightCrafter
            lightCrafter = edu.washington.riekelab.devices.LightCrafterDevice('micronsPerPixel', 0.8, 'host', 'ELMATADOR-PC', ...
                'ledCurrents',[0,11,50],...
                'customLightEngine',true);
            
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
            
            % Add the frame syncs
            frameMonitor = UnitConvertingDevice('Frame Sync', 'V').bindStream(obj.daqController.getStream('ai3'));
            obj.addDevice(frameMonitor);
        end
    end
end
