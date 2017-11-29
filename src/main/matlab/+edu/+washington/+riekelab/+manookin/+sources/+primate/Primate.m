classdef Primate < edu.washington.riekelab.manookin.sources.Subject
    
    methods
        
        function obj = Primate()
            import symphonyui.core.*;
            import edu.washington.*;
            
            obj.addProperty('species', '', ...
                'type', PropertyType('char', 'row', {'', 'M. mulatta', 'M. fascicularis', 'M. nemestrina','P. anubis'}), ... 
                'description', 'Species');
            
            photoreceptors = containers.Map();
            photoreceptors('lCone') = struct( ...
                'collectingArea', 0.37, ...
                'spectrum', importdata(riekelab.Package.getResource('photoreceptors', 'primate', 'l_cone_spectrum.txt')));
            photoreceptors('mCone') = struct( ...
                'collectingArea', 0.37, ...
                'spectrum', importdata(riekelab.Package.getResource('photoreceptors', 'primate', 'm_cone_spectrum.txt')));
            photoreceptors('rod') = struct( ...
                'collectingArea', 1.00, ...
                'spectrum', importdata(riekelab.Package.getResource('photoreceptors', 'primate', 'rod_spectrum.txt')));
            photoreceptors('sCone') = struct( ...
                'collectingArea', 0.37, ...
                'spectrum', importdata(riekelab.Package.getResource('photoreceptors', 'primate', 's_cone_spectrum.txt')));
            obj.addResource('photoreceptors', photoreceptors);
            
            obj.addAllowableParentType([]);
        end
        
    end
    
end

