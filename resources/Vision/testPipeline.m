
%addpath('C:\Users\Fred Rieke\Documents\manookin-package\StimulusPackages\base-package')
% addpath('/Volumes/GoogleDrive/My Drive/GitRepos/Symphony2/manookin-package/StimulusPackages/base-package/')
% m = manookinlab.network.MEAClient();
% m.connect('192.168.1.1', 9876);
% fname = m.getFileName(30)


m = MEAClient();
m.connect('10.0.0.18', 9876); %m.connect('10.0.0.18', 9876);

fname = m.getFileName(30)


strcmp(fname,'9999-99-99\data999.bin')