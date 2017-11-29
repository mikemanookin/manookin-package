classdef Mouse < edu.washington.riekelab.sources.Subject
    
    methods
        
        function obj = Mouse()
            import symphonyui.core.*;
            import edu.washington.*;
            
            obj.addProperty('genotype', {}, ...
                'type', PropertyType('cellstr', 'row', {'C57B6', 'Rho 19', 'Rho 18', 'STM', 'TTM', 'Arr1 KO', 'GRK1 KO', 'GCAP KO', 'GJD2-GFP', 'DACT2-GFP', 'PLCXD2-GFP', 'NeuroD6 Cre', 'Grm6-tdTomato', 'Grm6-cre1', 'Ai27 (floxed ChR2-tdTomato)', 'Cx36-/-'}), ... 
                'description', 'Genetic strain');
            
            photoreceptors = containers.Map();
            photoreceptors('mCone') = struct( ...
                'collectingArea', 0.20, ...
                'spectrum', importdata(riekelab.Package.getResource('photoreceptors', 'mouse', 'm_cone_spectrum.txt')));
            photoreceptors('rod') = struct( ...
                'collectingArea', 0.50, ...
                'spectrum', importdata(riekelab.Package.getResource('photoreceptors', 'mouse', 'rod_spectrum.txt')));
            photoreceptors('sCone') = struct( ...
                'collectingArea', 0.20, ...
                'spectrum', importdata(riekelab.Package.getResource('photoreceptors', 'mouse', 's_cone_spectrum.txt')));
            obj.addResource('photoreceptors', photoreceptors);
            
            obj.addAllowableParentType([]);
        end
        
    end
    
end

