function startStageServer()
    % Add Symphony to path
    appinfo = matlab.apputil.getInstalledAppInfo();
    for i = 1:numel(appinfo)
        if strcmp(appinfo(i).id, 'SymphonyAPP')
            addpath(genpath(appinfo(i).location));
            break;
        end
    end
    
    % Add Symphony search path to MATLAB path
    searchPath = symphonyui.app.Options.getDefault().searchPath;
    paths = strsplit(searchPath, ';');
    for i = 1:numel(paths)
        path = paths{i};
        
        % Find out if the path is in a git repo
        [rc, out] = system(['git -C "' path '" rev-parse']);
        if ~isempty(out) && isempty(strfind(out, 'Not a git repository'))
            warning(out);
        end
        
        % If the path is in a git repo
        if ~rc
            % Get the top-level path of the repo
            [rc, out] = system(['git -C "' path '" rev-parse --show-toplevel']);
            if rc
                warning(['Failed to get top-level git directory: ' out]);
            end
            path = strrep(out, sprintf('\n'), '');
        end
        
        addpath(genpath(path));
    end

    % Start Stage Server app
    matlab.apputil.run('StageServerAPP');
end