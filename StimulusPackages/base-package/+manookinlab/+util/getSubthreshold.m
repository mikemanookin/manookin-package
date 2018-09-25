function subThreshold = getSubthreshold(subThreshold, spikeTimes)
    % To generate the sub-threshold subthreshold potential, clip out the
    % spikes. Replace spikes using linear interpolation.
    window = 20; % The window of points to replace (half-size).
    replacePts = spikeTimes;
    %
    replacePts=replacePts(find(replacePts>(window+1) & replacePts<(replacePts(length(replacePts))-(window+1))));

    firstnum=subThreshold(replacePts-1-window);
    lastnum=subThreshold(replacePts+window);
    % loop through the length of the interpolation around each spike
    for i=1:(2*window+1)
        % calculate weights 
        lastwt=i/(2*window+1);
        firstwt=1-lastwt;
        % calculate new values of subthreshold around each spike
        subThreshold(replacePts+(i-1-window))=(firstwt.*firstnum) + (lastwt.*lastnum);
    end
end