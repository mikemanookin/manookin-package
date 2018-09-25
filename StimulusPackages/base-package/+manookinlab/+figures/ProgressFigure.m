classdef ProgressFigure < symphonyui.core.FigureHandler
    
    properties (SetAccess = private)
        totalNumEpochs
    end
    
    properties (Access = private)
        numEpochsCompleted
        intervalSeconds
        averageEpochDuration
        statusText
        progressBar
        timeText
    end
    
    methods
        
        function obj = ProgressFigure(totalNumEpochs, varargin)            
            ip = inputParser();
            ip.addParameter('intervalSeconds', 0, @(x)isscalar(x));
            ip.parse(varargin{:});
            
            obj.totalNumEpochs = double(totalNumEpochs);
            obj.numEpochsCompleted = 0;
            obj.intervalSeconds = ip.Results.intervalSeconds;
            
            obj.createUi();
            
            obj.updateProgress();
        end
        
        function createUi(obj)
            import appbox.*;
            
            mainLayout = uix.VBox( ...
                'Parent', obj.figureHandle, ...
                'Padding', 11);
            
            uix.Empty('Parent', mainLayout);
            
            progressLayout = uix.VBox( ...
                'Parent', mainLayout, ...
                'Spacing', 5);
            obj.statusText = Label( ...
                'Parent', progressLayout, ...
                'String', '', ...
                'HorizontalAlignment', 'left');
            obj.progressBar = javacomponent(javax.swing.JProgressBar(), [], progressLayout);
            obj.progressBar.setMaximum(obj.totalNumEpochs);
            obj.timeText = Label( ...
                'Parent', progressLayout, ...
                'String', '', ...
                'HorizontalAlignment', 'left');
            set(progressLayout, 'Heights', [23 20 23]);
            
            uix.Empty('Parent', mainLayout);
            
            set(mainLayout, 'Heights', [-1 23+5+20+5+23 -1]);
            
            set(obj.figureHandle, 'Name', 'Progress');
        end
        
        function handleEpoch(obj, epoch)
            obj.numEpochsCompleted = obj.numEpochsCompleted + 1;
            
            if isempty(obj.averageEpochDuration)
                obj.averageEpochDuration = epoch.duration;
            else
                obj.averageEpochDuration = obj.averageEpochDuration * (obj.numEpochsCompleted - 1)/obj.numEpochsCompleted + epoch.duration/obj.numEpochsCompleted;
            end
            
            obj.updateProgress();
        end
        
        function clear(obj)            
            obj.numEpochsCompleted = 0;
            obj.averageEpochDuration = [];
            
            obj.updateProgress();
        end
        
        function updateProgress(obj)
            set(obj.statusText, 'String', [num2str(obj.numEpochsCompleted) ' of ' num2str(obj.totalNumEpochs) ' epochs have completed']);
            
            obj.progressBar.setValue(obj.numEpochsCompleted);
            
            timeLeft = '';
            if ~isempty(obj.averageEpochDuration)
                n = obj.totalNumEpochs - obj.numEpochsCompleted;
                d = obj.averageEpochDuration * n + seconds(obj.intervalSeconds) * (n - 1);
                [h, m, s] = hms(d);
                if h >= 1
                    timeLeft = sprintf('%.0f hours, %.0f minutes', h, m);
                elseif minutes(d) >= 1
                    timeLeft = sprintf('%.0f minutes, %.0f seconds', m, s);
                else
                    timeLeft = sprintf('%.0f seconds', s);
                end
            end
            set(obj.timeText, 'String', ['Estimated time left: ' timeLeft]);
        end
        
    end
    
end