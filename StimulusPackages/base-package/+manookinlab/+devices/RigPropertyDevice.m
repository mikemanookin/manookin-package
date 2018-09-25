classdef RigPropertyDevice < symphonyui.core.Device
    methods
        function obj = RigPropertyDevice(laboratory, rigName)
            cobj = Symphony.Core.UnitConvertingExternalDevice(...
                'rigProperty',...
                'ManookinLab',...
                Symphony.Core.Measurement(0, symphonyui.core.Measurement.UNITLESS));
            obj@symphonyui.core.Device(cobj);
            obj.cobj.MeasurementConversionTarget = symphonyui.core.Measurement.UNITLESS;
            obj.addConfigurationSetting('laboratory', laboratory, 'isReadOnly', true);
            obj.addConfigurationSetting('rigName', rigName, 'isReadOnly', true);
        end
    end
end