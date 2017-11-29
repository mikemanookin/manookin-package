classdef Preparation < edu.washington.riekelab.manookin.sources.Preparation
    
    methods
        
        function obj = Preparation()
            import symphonyui.core.*;
            
            obj.addAllowableParentType('edu.washington.riekelab.manookin.sources.primate.Primate');
        end
        
    end
    
end

