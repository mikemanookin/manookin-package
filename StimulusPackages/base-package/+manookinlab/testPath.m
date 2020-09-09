
parentPath = fileparts(fileparts(fileparts(fileparts(((((mfilename('fullpath')))))))));

ids = strfind(parentPath,'\');
p = fullfile(parentPath(1:ids(end)-1),'movies')