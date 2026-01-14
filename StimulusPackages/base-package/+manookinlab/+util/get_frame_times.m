

f_cutoff = 300;

% Load the UCLA data.
d = load("/Users/michaelmanookin/Documents/GitRepos/Manookin-Lab/unit_test_data/UCLA/VideoMode/UCLAFrameMonitor.mat");
sample_rate = 1000;


%%
frame_monitor = d.frameMonitor(1,:);

% Create a butterworth filter.
[b, a] = butter(4, f_cutoff/(sample_rate/2), 'low'); % 4th order low-pass Butterworth filter with cutoff frequency at 0.1 * Nyquist frequency

% Apply the Butterworth filter to the frame monitor data
f_data = filtfilt(b, a, frame_monitor);

%%
x = frame_monitor;

min_value = max(0,min(x));
x = x - min_value;
x = x/max(x);
% Implement a Schmitt trigger.
refractory_samples = round(15/1000*sample_rate); % Refractory period in samples.
state = true; % Start high as the frame monitor initially triggered acquisition.
lock_counter = refractory_samples; % Initialize the lock counter.

up_times = [];
down_times = [];

threshold = 0.5; % Set the threshold for the Schmitt trigger
triggered = false(size(x)); % Initialize the triggered array
triggered(1) = state;
up_times = [up_times,1];
for i = 2:length(x)
    if lock_counter > 0
        lock_counter = lock_counter - 1; % Decrement the counter.
    else
        if ~state && x(i) >= threshold
            state = true; % Set state to low
            lock_counter = refractory_samples;
            up_times = [up_times,i]; %#ok<AGROW>
        elseif state && x(i) <= threshold
            state = false; % Reset state to high
            lock_counter = refractory_samples;
            down_times = [down_times,i]; %#ok<AGROW>
        end
    end
    triggered(i) = state;
end

frame_times = sort([up_times,down_times]);

foo = zeros(size(frame_monitor));
foo(up_times) = 1;

%% Check for valid up/down transitions.
threshold = 0.5; % Set the threshold for the frame transitions
refractory_time = 13; % Refractory period in msec.

% x = frame_monitor;
x = d.frameMonitor(2,:);

min_value = max(0,min(x));
x = x - min_value;
x = x/max(x);

% Transitions.
up_times = find((x(1:end-1) < threshold) & (x(2:end) >= threshold));
down_times = find((x(1:end-1) > threshold) & (x(2:end) <= threshold));

% Implement a Schmitt trigger.
refractory_samples = round(refractory_time/1000*sample_rate); % Refractory period in samples.

% Check for validity of down times.
valid_ups = false(size(up_times));
valid_downs = false(size(down_times));
for ii = 1 : length(down_times)
    % Find the up time the follows closest after this down time.
    up_diff = up_times - down_times(ii);
    if any(up_diff > 0)
        up_diff(up_diff <= 0) = Inf;
        [~,sorted_idx] = sort(up_diff);
        if up_diff(sorted_idx(1)) >= refractory_samples
            valid_downs(ii) = true;
            valid_ups(sorted_idx(1)) = true;
        end
    else
        valid_downs(ii) = 1;
    end
end

frame_times = sort([up_times(valid_ups),down_times(valid_downs)]);

foo = zeros(size(frame_monitor));
foo(frame_times) = 1;

figure(100); clf;
hold on
plot(x)
plot(foo)
hold off;
set(gca,'XLim',[0,200])

