classdef LcrPatternAmp1 < symphonyui.core.descriptions.RigDescription
    
    methods
        function obj = LcrPatternAmp1()
            import symphonyui.builtin.daqs.*;
            import symphonyui.builtin.devices.*;
            import symphonyui.core.*;
            
            daq = HekaDaqController();
            obj.daqController = daq;
            
            amp1 = MultiClampDevice('Amp1', 1).bindStream(daq.getStream('ao0')).bindStream(daq.getStream('ai0'));
            obj.addDevice(amp1);
            
            temperature = UnitConvertingDevice('Temperature Controller', 'V', 'manufacturer', 'Warner Instruments').bindStream(daq.getStream('ai7'));
            obj.addDevice(temperature);
            
            % Add the frame monitor
            frameMonitor = UnitConvertingDevice('Frame Monitor', 'V').bindStream(obj.daqController.getStream('ai2'));
            obj.addDevice(frameMonitor);
            
            trigger = UnitConvertingDevice('Oscilloscope Trigger', symphonyui.core.Measurement.UNITLESS).bindStream(daq.getStream('doport1'));
            daq.getStream('DIGITAL_OUT.1').setBitPosition(trigger, 0);
            obj.addDevice(trigger);
            
            % Add the LightCrafter
            lightCrafter = edu.washington.riekelab.devices.LightCrafterDevice('micronsPerPixel', 0.67);
            obj.addDevice(lightCrafter);
            
            % Add the filter wheel.
            filterWheel = manookinlab.devices.FilterWheelDevice('comPort', 'COM13');
            
            % Binding the filter wheel to an unused stream only so its configuration settings are written to each epoch.
            daq = obj.daqController;
            filterWheel.bindStream(daq.getStream('doport1'));
            daq.getStream('DIGITAL_OUT.1').setBitPosition(filterWheel, 15);
            
            obj.addDevice(filterWheel);
        end
    end
end