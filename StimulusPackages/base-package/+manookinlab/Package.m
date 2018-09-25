classdef Package < handle
    
    methods (Static)
        
        function p = getCalibrationResource(varargin)
            parentPath = fileparts(fileparts(fileparts(fileparts(((((mfilename('fullpath')))))))));
            calibrationPath = fullfile(parentPath, 'calibration-resources');
%             if ~exist(calibrationPath, 'dir')
%                 [rc, ~] = system(['git clone https://github.com/Rieke-Lab/calibration-resources.git "' calibrationPath '"']);
%                 if rc
%                     error(['Cannot find or clone calibration-resources directory. Expected to exist: ' calibrationPath]);
%                 end
%             end
            p = fullfile(calibrationPath, varargin{:});
        end
        
        function p = getResourcePath()
            parentPath = fileparts(fileparts(fileparts(fileparts(((((mfilename('fullpath')))))))));
            p = fullfile(parentPath, 'resources');
        end
    end
    
end

