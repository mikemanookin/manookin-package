classdef (Abstract) EpochGroup < symphonyui.core.persistent.descriptions.EpochGroupDescription
    
    methods
        
        function obj = EpochGroup()
            import symphonyui.core.*;
            
            obj.addProperty('externalSolutionAdditions', {}, ...
                'type', PropertyType('cellstr', 'row', {'14 mM D-glucose','NBQX (10uM)', 'DAPV (50uM)', 'APB (5uM)', 'LY 341495 (7.5uM)', 'strychnine (0.5uM)', 'strychnine (25uM)', 'gabazine (10uM)', 'gabazine (25uM)', 'TPMPA (50uM)', 'TTX (100nM)', 'TTX (500nM)', 'HEX (100uM)','MLA (100nM)'}));
            obj.addProperty('pipetteSolution', '', ...
                'type', PropertyType('char', 'row', {'', 'cesium', 'cesium 0.5% biocytin', 'potassium', 'potassium 1% biocytin', 'potassium zero calcium buffer', 'full chloride cesium', 'Ames'}));
            obj.addProperty('internalSolutionAdditions', '');
            obj.addProperty('recordingTechnique', '', ...
                'type', PropertyType('char', 'row', {'', 'EXTRACELLULAR','EXCITATION','INHIBITION', 'CURRENT_CLAMP', 'VOLTAGE_CLAMP', 'DYNAMIC_CLAMP', 'OPTICAL'}));
            obj.addProperty('seriesResistanceCompensation', int32(0), ...
                'type', PropertyType('int32', 'scalar', [0 100]));
            
            % Quality property
            obj.addProperty('quality', '', ...
                'type', PropertyType('char', 'row', {'', 'EXCELLENT', 'HIGH', 'MEDIUM','LOW'}));
        end
        
    end
    
end

