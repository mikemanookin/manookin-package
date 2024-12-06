classdef DownstairsLeft < symphonyui.core.descriptions.RigDescription
    
    methods
        function obj = DownstairsLeft()
            import symphonyui.builtin.daqs.*;
            import symphonyui.builtin.devices.*;
            import symphonyui.core.*;
            import edu.washington.*;
            
            daq = HekaDaqController();
            obj.daqController = daq;
            daq = obj.daqController;
            
            % MultiClamp device.
            amp1 = MultiClampDevice('Amp1', 1).bindStream(daq.getStream('ao0')).bindStream(daq.getStream('ai0'));
            obj.addDevice(amp1);

            % Get calibration resources.
            ramps = containers.Map();
            ramps('red')    = 65535 * importdata(manookinlab.Package.getCalibrationResource('rigs', 'downstairs_left', 'red_gamma_ramp.txt'));
            ramps('green')  = 65535 * importdata(manookinlab.Package.getCalibrationResource('rigs', 'downstairs_left', 'green_gamma_ramp.txt'));
            ramps('blue')   = 65535 * importdata(manookinlab.Package.getCalibrationResource('rigs', 'downstairs_left', 'blue_gamma_ramp.txt'));
            
            % Add the LightCrafter
            lightCrafter = manookinlab.devices.LcrVideoDevice(...
                'micronsPerPixel', 2.76, ...
                'gammaRamps', ramps, ...
                'host', 'ELMATADOR-PC', ...
                'local_movie_directory','C:\Users\Public\Documents\GitRepos\Symphony2\movies\',...
                'stage_movie_directory','Y:\\movies\',...
                'ledCurrents', [10,25,50],...
                'customLightEngine', true);
            % Binding the lightCrafter to an unused stream only so its configuration settings are written to each epoch.
            lightCrafter.bindStream(daq.getStream('doport1'));
            daq.getStream('doport1').setBitPosition(lightCrafter, 15);

            lightCrafter.addResource('fluxFactorPaths', containers.Map( ...
                {'auto', 'red', 'green', 'blue'}, { ...
                manookinlab.Package.getCalibrationResource('rigs', 'downstairs_left', 'lightcrafter_above_auto_flux_factors.txt'), ...
                manookinlab.Package.getCalibrationResource('rigs', 'downstairs_left', 'lightcrafter_above_red_flux_factors.txt'), ...
                manookinlab.Package.getCalibrationResource('rigs', 'downstairs_left', 'lightcrafter_above_green_flux_factors.txt'), ...
                manookinlab.Package.getCalibrationResource('rigs', 'downstairs_left', 'lightcrafter_above_blue_flux_factors.txt')}));
            lightCrafter.addConfigurationSetting('lightPath', 'above', 'isReadOnly', true);
            
            % Add the LED spectra.
            lightCrafter.addResource('spectrum', containers.Map( ...
                {'auto', 'red', 'green', 'blue'}, { ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'downstairs_left', 'lightcrafter_above_auto_spectrum.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'downstairs_left', 'lightcrafter_above_red_spectrum.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'downstairs_left', 'lightcrafter_above_green_spectrum.txt')), ...
                importdata(manookinlab.Package.getCalibrationResource('rigs', 'downstairs_left', 'lightcrafter_above_blue_spectrum.txt'))}));  

            lightCrafter.addConfigurationSetting('ndfs', {}, ...
                'type', PropertyType('cellstr', 'row', {'FW00', 'FW05', 'FW10', 'FW20', 'FW30', 'FW40', 'H03', 'H06', 'H10', 'H20'}));
            lightCrafter.addResource('ndfAttenuations', containers.Map( ...
                {'auto','red', 'green', 'blue'}, { ...
                containers.Map( ...
                    {'FW00', 'FW05', 'FW10', 'FW20', 'FW30', 'FW40', 'H03', 'H06', 'H10', 'H20'}, ...
                    {0, 0.5054, 0.9961, 2.1100, 3.1363, 4.1918, 0.2866, 0.5933, 0.9675, 1.9279}), ...
                containers.Map( ...
                    {'FW00', 'FW05', 'FW10', 'FW20', 'FW30', 'FW40', 'H03', 'H06', 'H10', 'H20'}, ...
                    {0, 0.5082, 1.0000, 2.0152, 3.0310, 4.0374, 0.2866, 0.5933, 0.9675, 1.9279}), ...
                containers.Map( ...
                    {'FW00', 'FW05', 'FW10', 'FW20', 'FW30', 'FW40', 'H03', 'H06', 'H10', 'H20'}, ...
                    {0, 0.5054, 0.9961, 2.1100, 3.1363, 4.1918, 0.2866, 0.5933, 0.9675, 1.9279}), ...
                containers.Map( ...
                    {'FW00', 'FW05', 'FW10', 'FW20', 'FW30', 'FW40', 'H03', 'H06', 'H10', 'H20'}, ...
                    {0, 0.5305, 1.0502, 2.4253, 3.6195, 4.8356, 0.2663, 0.5389, 0.9569, 2.0810})}));

            % Compute the quantal catch and add it to the rig config.
            paths = lightCrafter.getResource('fluxFactorPaths');
            spectrum = lightCrafter.getResource('spectrum');
            qCatch = manookinlab.util.computePhotoreceptorCatch(paths, spectrum, 'species', 'macaque');
            lightCrafter.addResource('quantalCatch', qCatch);
            obj.addDevice(lightCrafter);

            % Add the red LED.
            red = UnitConvertingDevice('Red LED', 'V').bindStream(daq.getStream('ao1'));
            obj.addDevice(red);
            
            % Add the green and blue LEDs
            green = UnitConvertingDevice('Green LED', 'V').bindStream(daq.getStream('ao2'));
            obj.addDevice(green);
            
            blue = UnitConvertingDevice('Blue LED', 'V').bindStream(daq.getStream('ao3'));
            obj.addDevice(blue);
%             
            temperature = UnitConvertingDevice('Temperature Controller', 'V', 'manufacturer', 'Warner Instruments').bindStream(daq.getStream('ai7'));
            obj.addDevice(temperature);
            
            % Add the frame monitor
            frameMonitor = UnitConvertingDevice('Frame Monitor', 'V').bindStream(obj.daqController.getStream('ai2'));
            obj.addDevice(frameMonitor);
            
            trigger = UnitConvertingDevice('Oscilloscope Trigger', symphonyui.core.Measurement.UNITLESS).bindStream(daq.getStream('doport1'));
            daq.getStream('doport1').setBitPosition(trigger, 0);
            obj.addDevice(trigger);
            
            % Add the filter wheel.
            filterWheel = riekelab.devices.FilterWheelDevice('comPort', 'COM3');
            
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