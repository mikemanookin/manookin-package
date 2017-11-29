
d = load('C:\Users\manoo\Google Drive\Calibrations\20171120\Spectra.mat');
ledNames = {
    'red';
    'Green_505nm';
    'Green_570nm';
    'blue';
    };

for k = 1 : length(ledNames)
    fid = fopen([ledNames{k},'_spectrum.txt'],'wt');
    for m = 1 : size(energySpectra,1)
        fprintf(fid,'%e\n',energySpectra(m,k));
    end
    fclose(fid);
end

q = load('C:\Users\manoo\Google Drive\Calibrations\20171120\QCatch.mat');

ndfNames = {
    'ndf00', 'ndf05', 'ndf10', 'ndf20', 'ndf30', 'ndf40'
    };

for k = 1 : length(ndfNames)
    fid = fopen([ndfNames{k},'_catch.txt'],'wt');
    Q = q.qCatch.(ndfNames{k});
    for m = 1 : size(Q,1)
        fprintf(fid,'%e ',Q(m,:));
        fprintf(fid,'\n');
    end
    
    fclose(fid);
end
