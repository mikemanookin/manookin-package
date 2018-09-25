function results = spikeDetectorOnline(D,thresh,sampleRate)
%For online analysis
%D is matrix of spike recording data
%Thresh is deflection threshold to call an event a spike and not noise
%If no thresh, automatically uses 1/3 maximum deflection amplitude as
%threshold
%This does a pretty good job for big-ish spikes, and it's fast. I would use
%something a little more versatile for offline analysis, though

%MHT 080514

% AIW 121014
% Added section "make sure detected spikes aren't just noise"
% Previously, code would find many spikes on trials with no spikes

if (nargin<2)
    thresh = []; %define on trace-by-trace basis automatically, as 1/3rd of maximum deflection. Decent job.
    sampleRate = 1e4; %Hz, default at 10kHz
end
HighPassCut_spikes = 500; %Hz, in order to remove everything but spikes
SampleInterval = sampleRate^-1;
ref_period = 2E-3; %s
ref_period_points = round(ref_period./SampleInterval); %data points

[Ntraces,L] = size(D);
% Dhighpass = highPassFilter(D,HighPassCut_spikes,SampleInterval);
Dhighpass = manookinlab.util.DB4Filter(D(:)', 6);

%initialize output stuff...
sp = cell(Ntraces,1);
spikeAmps = cell(Ntraces,1);
violation_ind = cell(Ntraces,1);

for i=1:Ntraces
    %get the trace
    trace = Dhighpass(i,:);
    trace = trace - median(trace); %remove baseline
    if abs(max(trace)) < abs(min(trace)) %flip it over
        trace = -trace;
    end
    if isempty(thresh)
        thresh = max(trace)/3;
    end
    

    %get peaks
    [peaks,peak_times] = manookinlab.util.getPeaks(trace,1); %positive peaks
    peak_times = peak_times(peaks>0); %only positive deflections
    peaks = trace(peak_times);
    peak_times = peak_times(peaks>thresh);      
    peaks = peaks(peaks>thresh);
    
    %%% make sure detected spikes aren't just noise
    peakIdx = zeros(size(trace));
    peakIdx(peak_times) = 1;
    nonspike_peaks = trace(~peakIdx); % trace values at time points that weren't detected as spikes
    % compare magnitude of detected spikes to trace values that aren't "spikes"
    if mean((peaks)) < mean((nonspike_peaks)) + 4*std((nonspike_peaks)); % avg spike must be 4 stdevs from average non-spike, otherwise no spikes
        peak_times = [];
        peaks = [];
    end
    %%%
    
    sp{i} = peak_times;
    spikeAmps{i} = peaks;
    violation_ind{i} = find(diff(sp{i})<ref_period_points) + 1;
end

if length(sp) == 1 %return vector not cell array if only 1 trial
    sp = sp{1};
    spikeAmps = spikeAmps{1};    
    violation_ind = violation_ind{1};
end

results.sp = sp; %spike times (data points)
results.spikeAmps = spikeAmps;
results.violation_ind = violation_ind; %refractory violations in results.sp
