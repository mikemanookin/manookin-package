classdef Preparation < manookinlab.sources.Preparation
    
    methods
        
        function obj = Preparation()
            import symphonyui.core.*;
            
            obj.addAllowableParentType('manookinlab.sources.primate.Primate');
        end
        
    end
    
end

