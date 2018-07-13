classdef LcrVideoOneAmp < symphonyui.core.descriptions.RigDescription
    
    methods
        function obj = LcrVideoOneAmp()
            import symphonyui.builtin.daqs.*;
            import symphonyui.builtin.devices.*;
            import symphonyui.core.*;
            
            daq = HekaDaqController();
            obj.daqController = daq;
            
            amp1 = MultiClampDevice('Amp1', 1).bindStream(daq.getStream('ao0')).bindStream(daq.getStream('ai0'));
            obj.addDevice(amp1);
            
            amp2 = MultiClampDevice('Amp2', 1).bindStream(daq.getStream('ao1')).bindStream(daq.getStream('ai1'));
            obj.addDevice(amp2);
            
            % Add the frame monitor
            frameMonitor = UnitConvertingDevice('Frame Monitor', 'V').bindStream(obj.daqController.getStream('ai2'));
            obj.addDevice(frameMonitor);
            
%             % Add the PMTs and SciScan clocks.
%             pmtA = UnitConvertingDevice('PMT A', 'V', 'manufacturer', 'Scientifica').bindStream(daq.getStream('ANALOG_IN.3'));
%             obj.addDevice(pmtA);
%             
%             pmtB = UnitConvertingDevice('PMT B', 'V', 'manufacturer', 'Scientifica').bindStream(daq.getStream('ANALOG_IN.4'));
%             obj.addDevice(pmtB);
%             
%             frameClock = UnitConvertingDevice('SciScan Frame Clock', 'V', 'manufacturer', 'Scientifica').bindStream(daq.getStream('ANALOG_IN.5'));
%             obj.addDevice(frameClock);
%             
%             sampleClock = UnitConvertingDevice('SciScan Sample Clock', 'V', 'manufacturer', 'Scientifica').bindStream(daq.getStream('ANALOG_IN.6'));
%             obj.addDevice(sampleClock);
            
            % Add the bath temperature.
            temperature = UnitConvertingDevice('Temperature Controller', 'V', 'manufacturer', 'Warner Instruments').bindStream(daq.getStream('ai7'));
            obj.addDevice(temperature);
            
            trigger = UnitConvertingDevice('Oscilloscope Trigger', symphonyui.core.Measurement.UNITLESS).bindStream(daq.getStream('doport1'));
            daq.getStream('doport1').setBitPosition(trigger, 0);
            obj.addDevice(trigger);
            
            % Add the LightCrafter
            lightCrafter = manookinlab.devices.LcrVideoDevice('micronsPerPixel', 0.6727);
            obj.addDevice(lightCrafter);
            
            % Add the filter wheel.
            filterWheel = manookinlab.devices.FilterWheelDevice('comPort', 'COM13');
            
            % Binding the filter wheel to an unused stream only so its configuration settings are written to each epoch.
            daq = obj.daqController;
            filterWheel.bindStream(daq.getStream('doport1'));
            daq.getStream('doport1').setBitPosition(filterWheel, 15);
            
            obj.addDevice(filterWheel);
            
            
        end
    end
end