classdef FilterWheelControl < symphonyui.ui.Module
    
    properties (Access = private)
        stage
        filterWheel
        ndf
        objectiveMag
        ndfSettingPopupMenu
        objectivePopupMenu
        ledPopupMenu
        greenLEDName
        maxLText
        maxMText
        maxSText
        maxRodText
        quantalCatch
        q
    end
    
    methods
        
        function createUi(obj, figureHandle)
            import appbox.*;
            
            set(figureHandle, ...
                'Name', 'ND Wheel Control', ...
                'Position', screenCenter(200, 200));
            
            mainLayout = uix.HBox( ...
                'Parent', figureHandle, ...
                'Padding', 11, ...
                'Spacing', 7);
            
            filterWheelLayout = uix.Grid( ...
                'Parent', mainLayout, ...
                'Spacing', 7);
            Label( ...
                'Parent', filterWheelLayout, ...
                'String', 'NDF:');
            Label( ...
                'Parent', filterWheelLayout, ...
                'String', 'Objective:');
            Label( ...
                'Parent', filterWheelLayout, ...
                'String', 'LED switch position:');
            Label( ...
                'Parent', filterWheelLayout, ...
                'String', 'L-cone max: ');
            Label( ...
                'Parent', filterWheelLayout, ...
                'String', 'M-cone max: ');
            Label( ...
                'Parent', filterWheelLayout, ...
                'String', 'S-cone max: ');
            Label( ...
                'Parent', filterWheelLayout, ...
                'String', 'rod max: ');
            obj.ndfSettingPopupMenu = MappedPopupMenu( ...
                'Parent', filterWheelLayout, ...
                'String', {' '}, ...
                'HorizontalAlignment', 'left', ...
                'Callback', @obj.onSelectedNdfSetting);
            obj.objectivePopupMenu = MappedPopupMenu( ...
                'Parent', filterWheelLayout, ...
                'String', {' '}, ...
                'HorizontalAlignment', 'left', ...
                'Callback', @obj.onSelectedObjectiveSetting);
            obj.ledPopupMenu = MappedPopupMenu( ...
                'Parent', filterWheelLayout, ...
                'String', {' '}, ...
                'HorizontalAlignment', 'left', ...
                'Callback', @obj.onSelectedLedSetting);
            obj.maxLText = uicontrol( ...
                'Parent', filterWheelLayout, ...
                'Style', 'text', ...
                'HorizontalAlignment', 'left', ...
                'String', '0.0 R*/sec');
            obj.maxMText = uicontrol( ...
                'Parent', filterWheelLayout, ...
                'Style', 'text', ...
                'HorizontalAlignment', 'left', ...
                'String', '0.0 R*/sec');
            obj.maxSText = uicontrol( ...
                'Parent', filterWheelLayout, ...
                'Style', 'text', ...
                'HorizontalAlignment', 'left', ...
                'String', '0.0 R*/sec');
            obj.maxRodText = uicontrol( ...
                'Parent', filterWheelLayout, ...
                'Style', 'text', ...
                'HorizontalAlignment', 'left', ...
                'String', '0.0 R*/sec');
            set(filterWheelLayout, ...
                'Widths', [70 -1], ...
                'Heights', 23*ones(1,7));
        end
        
    end
    
    methods (Access = protected)
        
        function willGo(obj)
            devices = obj.configurationService.getDevices('FilterWheel');
            if isempty(devices)
                error('No filterWheel device found');
            end
            
            obj.filterWheel = devices{1};
            
            obj.populateNdfSettingList();
            
            obj.populateObjectiveList();
            
            obj.populateLedList();
            
            % Set the NDF to 4.0 on startup.
            obj.filterWheel.setNDF(4);
            set(obj.ndfSettingPopupMenu, 'Value', 4);
            
            % Load up the quantal catch struct.
            obj.loadQuantalCatch();
            obj.setQuantalCatch();
        end
        
    end
    
    methods (Access = private)
        function populateNdfSettingList(obj)
            ndfNums = {0.0, 0.5, 1.0, 2.0, 3.0, 4.0};
            ndfs = {'0.0', '0.5', '1.0', '2.0', '3.0', '4.0'}; 
            
            set(obj.ndfSettingPopupMenu, 'String', ndfs);
            set(obj.ndfSettingPopupMenu, 'Values', ndfNums);
        end
        
        function onSelectedNdfSetting(obj, ~, ~)
            position = get(obj.ndfSettingPopupMenu, 'Value');
            obj.filterWheel.setNDF(position);
            obj.setQuantalCatch();
        end
        
        function populateObjectiveList(obj)
            objectiveNums = {60, 10, 4};
            objectiveStrings = {'60x', '10x', '4x'};
            
            set(obj.objectivePopupMenu, 'String', objectiveStrings);
            set(obj.objectivePopupMenu, 'Values', objectiveNums);
            obj.objectiveMag = 60;
        end
        
        function onSelectedObjectiveSetting(obj, ~, ~)
            v = get(obj.objectivePopupMenu, 'Value');
            obj.filterWheel.setObjective(v);
            obj.objectiveMag = v;
            obj.setQuantalCatch();
        end
        
        function populateLedList(obj)
            ledValues = {'Green_505nm', 'Green_570nm'};
            ledStrings = {'Green_505nm', 'Green_570nm'};
            set(obj.ledPopupMenu, 'String', ledStrings);
            set(obj.ledPopupMenu, 'Values', ledValues);
        end
        
        function onSelectedLedSetting(obj, ~, ~)
            v = get(obj.ledPopupMenu, 'Value');
            obj.greenLEDName = v;
            obj.filterWheel.setGreenLEDName(v);
            obj.setQuantalCatch();
        end
        
        function loadQuantalCatch(obj)
            % Get the quantal catch.
            obj.q = load('QCatch.mat');
        end
        
        function setQuantalCatch(obj)
            obj.objectiveMag = obj.filterWheel.getObjective();
            obj.greenLEDName = obj.filterWheel.getGreenLEDName();
                
            % Get the NDF wheel setting.
            obj.ndf = obj.filterWheel.getNDF();
            ndString = num2str(obj.ndf * 10);
            if length(ndString) == 1
                ndString = ['0', ndString];
            end
            if strcmp(obj.greenLEDName, 'Green_505nm')
                obj.quantalCatch = obj.q.qCatch.(['ndf', ndString])([1 2 4],:);
            else
                obj.quantalCatch = obj.q.qCatch.(['ndf', ndString])([1 3 4],:);
            end
            % Adjust the quantal catch depending on the objective.
            if obj.objectiveMag == 4
                obj.quantalCatch = obj.quantalCatch .* ([0.498627; 0.4921139; 0.453983]*ones(1,4));
            elseif obj.objectiveMag == 60
                obj.quantalCatch = obj.quantalCatch .* ([1.867747065682890; 1.849862001274647; 1.767678539504911]*ones(1,4));
            end
            
            % Set the quantal catch on the filter wheel device.
            obj.filterWheel.setQuantalCatch(obj.quantalCatch);
            
            % Calculate the max values.
            m = sum(obj.quantalCatch);
            set(obj.maxLText, 'String', [obj.formatNumbers(m(1)), ' R*/sec']);
            set(obj.maxMText, 'String', [obj.formatNumbers(m(2)), ' R*/sec']);
            set(obj.maxSText, 'String', [obj.formatNumbers(m(3)), ' R*/sec']);
            set(obj.maxRodText, 'String', [obj.formatNumbers(m(4)), ' R*/sec']);
        end
        
    end
    
    methods (Static)
        function numString = formatNumbers(num)
            if num > 10
                num = round(num);
                numString = sprintf(',%c%c%c',fliplr(num2str(num)));
                numString = fliplr(numString(2:end));
            else
                numString = num2str(round(num*10)/10);
            end
        end
    end
    
end