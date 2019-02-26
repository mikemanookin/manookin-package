classdef LcrVideoControl < symphonyui.ui.Module
    
    properties (Access = private)
        log
        settings
        lightCrafter
        ledEnablesCheckboxes
        patternRatePopupMenu
        centerOffsetFields
        prerenderCheckbox
    end
    
    methods
        
        function obj = LcrVideoControl()
            obj.log = log4m.LogManager.getLogger(class(obj));
            obj.settings = edu.washington.riekelab.modules.settings.LightCrafterControlSettings();
        end
        
        function createUi(obj, figureHandle)
            import appbox.*;
            
            set(figureHandle, ...
                'Name', 'LightCrafter Control', ...
                'Position', screenCenter(350, 135), ...
                'Resize', 'off');
            
            mainLayout = uix.HBox( ...
                'Parent', figureHandle, ...
                'Padding', 11, ...
                'Spacing', 7);
            
            lightCrafterLayout = uix.Grid( ...
                'Parent', mainLayout, ...
                'Spacing', 7);
            Label( ...
                'Parent', lightCrafterLayout, ...
                'String', 'LED enables:');
            Label( ...
                'Parent', lightCrafterLayout, ...
                'String', 'Pattern rate:');
            Label( ...
                'Parent', lightCrafterLayout, ...
                'String', 'Center offset (um):');
            Label( ...
                'Parent', lightCrafterLayout, ...
                'String', 'Prerender:');
            ledEnablesLayout = uix.HBox( ...
                'Parent', lightCrafterLayout, ...
                'Spacing', 3);
            obj.ledEnablesCheckboxes.auto = uicontrol( ...
                'Parent', ledEnablesLayout, ...
                'Style', 'checkbox', ...
                'String', 'Auto', ...
                'Callback', @obj.onSelectedLedEnable);
            obj.ledEnablesCheckboxes.red = uicontrol( ...
                'Parent', ledEnablesLayout, ...
                'Style', 'checkbox', ...
                'HorizontalAlignment', 'left', ...
                'String', 'Red', ...
                'Callback', @obj.onSelectedLedEnable);
            obj.ledEnablesCheckboxes.green = uicontrol( ...
                'Parent', ledEnablesLayout, ...
                'Style', 'checkbox', ...
                'HorizontalAlignment', 'left', ...
                'String', 'Green', ...
                'Callback', @obj.onSelectedLedEnable);
            obj.ledEnablesCheckboxes.blue = uicontrol( ...
                'Parent', ledEnablesLayout, ...
                'Style', 'checkbox', ...
                'HorizontalAlignment', 'left', ...
                'String', 'Blue', ...
                'Callback', @obj.onSelectedLedEnable);
            obj.patternRatePopupMenu = MappedPopupMenu( ...
                'Parent', lightCrafterLayout, ...
                'String', {' '}, ...
                'HorizontalAlignment', 'left', ...
                'Callback', @obj.onSelectedPatternRate);
            offsetLayout = uix.HBox( ...
                'Parent', lightCrafterLayout, ...
                'Spacing', 5);
            obj.centerOffsetFields.x = uicontrol( ...
                'Parent', offsetLayout, ...
                'Style', 'edit', ...
                'HorizontalAlignment', 'left', ...
                'Callback', @obj.onSetCenterOffset);
            Label( ...
                'Parent', offsetLayout, ...
                'String', 'X');
            obj.centerOffsetFields.y = uicontrol( ...
                'Parent', offsetLayout, ...
                'Style', 'edit', ...
                'HorizontalAlignment', 'left', ...
                'Callback', @obj.onSetCenterOffset);
            Label( ...
                'Parent', offsetLayout, ...
                'String', 'Y');
            set(offsetLayout, ...
                'Widths', [-1 8+5 -1 8]);
            obj.prerenderCheckbox = uicontrol( ...
                'Parent', lightCrafterLayout, ...
                'Style', 'checkbox', ...
                'String', '', ...
                'Callback', @obj.onSelectedPrerender);
            
            set(lightCrafterLayout, ...
                'Widths', [100 -1], ...
                'Heights', [23 23 23 23]);
        end
        
    end
    
    methods (Access = protected)
        
        function willGo(obj)
            devices = obj.configurationService.getDevices('LcrVideo');
            if isempty(devices)
                error('No LightCrafter device found');
            end
            
            obj.lightCrafter = devices{1};
            
            obj.populateLedEnables();
            obj.populatePatternRateList();
            obj.populateCenterOffset();
            obj.populatePrerender();
            
            try
                obj.loadSettings();
            catch x
                obj.log.debug(['Failed to load settings: ' x.message], x);
            end
        end
        
        function willStop(obj)
            try
                obj.saveSettings();
            catch x
                obj.log.debug(['Failed to save settings: ' x.message], x);
            end
        end
        
    end
    
    methods (Access = private)
        
        function populateLedEnables(obj)
            [auto, red, green, blue] = obj.lightCrafter.getLedEnables();
            set(obj.ledEnablesCheckboxes.auto, 'Value', auto);
            set(obj.ledEnablesCheckboxes.red, 'Value', red);
            set(obj.ledEnablesCheckboxes.green, 'Value', green);
            set(obj.ledEnablesCheckboxes.blue, 'Value', blue);
        end
        
        function onSelectedLedEnable(obj, ~, ~)
            auto = get(obj.ledEnablesCheckboxes.auto, 'Value');
            red = get(obj.ledEnablesCheckboxes.red, 'Value');
            green = get(obj.ledEnablesCheckboxes.green, 'Value');
            blue = get(obj.ledEnablesCheckboxes.blue, 'Value');
            obj.lightCrafter.setLedEnables(auto, red, green, blue);
        end
        
        function populatePatternRateList(obj)
            rates = obj.lightCrafter.availablePatternRates();
            names = cellfun(@(r)[num2str(r) ' Hz'], rates, 'UniformOutput', false); 
            
            set(obj.patternRatePopupMenu, 'String', names);
            set(obj.patternRatePopupMenu, 'Values', rates);
            
            set(obj.patternRatePopupMenu, 'Value', obj.lightCrafter.getPatternRate());
        end
        
        function onSelectedPatternRate(obj, ~, ~)
            rate = get(obj.patternRatePopupMenu, 'Value');
            obj.lightCrafter.setPatternRate(rate);
        end
        
        function populateCenterOffset(obj)
            offset = obj.lightCrafter.pix2um(obj.lightCrafter.getCenterOffset());
            set(obj.centerOffsetFields.x, 'String', num2str(offset(1)));
            set(obj.centerOffsetFields.y, 'String', num2str(offset(2)));
        end
        
        function onSetCenterOffset(obj, ~, ~)
            x = str2double(get(obj.centerOffsetFields.x, 'String'));
            y = str2double(get(obj.centerOffsetFields.y, 'String'));
            if isnan(x) || isnan(y)
                obj.view.showError('Could not parse x or y to a valid scalar value.');
                return;
            end
            obj.lightCrafter.setCenterOffset(obj.lightCrafter.um2pix([x, y]));
        end
        
        function populatePrerender(obj)
            set(obj.prerenderCheckbox, 'Value', obj.lightCrafter.getPrerender());
        end
        
        function onSelectedPrerender(obj, ~, ~)
            prerender = get(obj.prerenderCheckbox, 'Value');
            obj.lightCrafter.setPrerender(prerender);
        end
        
        function loadSettings(obj)
            if ~isempty(obj.settings.viewPosition)
                p1 = obj.view.position;
                p2 = obj.settings.viewPosition;
                obj.view.position = [p2(1) p2(2) p1(3) p1(4)];
            end
        end

        function saveSettings(obj)
            obj.settings.viewPosition = obj.view.position;
            obj.settings.save();
        end
        
    end
    
end

