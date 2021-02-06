function [isiH,isiEdges] = getSpikeAutocorrelation(isi)

% Get the interspike interval histogram
isiEdges = 1:101;
isiH = histcounts(isi, isiEdges, 'Normalization','probability');

isiEdges = isiEdges(1:end-1);
