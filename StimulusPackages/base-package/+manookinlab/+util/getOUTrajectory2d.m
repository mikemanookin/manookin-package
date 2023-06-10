function positions = getOUTrajectory2d(duration, seed, varargin)

ip = inputParser();
ip.addParameter('correlationDecayTau', 20, @(x)isfloat(x));
ip.addParameter('frameRate', 60.0, @(x)isfloat(x));
ip.addParameter('motionSpeed', 700.0, @(x)isfloat(x)); % Motion speed in pixels / sec
ip.addParameter('noiseClass','gaussian',@(x)ischar(x));

% Parse the inputs.
ip.parse(varargin{:});

% Get the field names from the input parser.
fnames = fieldnames(ip.Results);

% Create the parameters structure.
params = struct();
for jj = 1 : length(fnames)
    params.(fnames{jj}) = ip.Results.(fnames{jj});
end

dt = 1 / params.frameRate;
T = 0 : dt : (duration+40)-dt;

D_OU = 2.7e6; %dynamical range

% Get your position vector (x,y).
positions = zeros(length(T), 2);
% Velocity vectors (x,y)
V = zeros(length(T), 2);

if strcmpi(params.noiseClass,'gaussian_randn')
    rng(seed,'twister');
    v_noise = manookinlab.util.gaussian_randn(length(T), 2);
else
    positionStream = RandStream('mt19937ar', 'Seed', seed);
    v_noise = positionStream.randn(length(T), 2);
end

% Update the velocities and positions on each time step according to the
% OU algorithm.
for t = 1 : length(T)-1
    positions(t+1,:) = (1-dt*params.correlationDecayTau/(2.12)^2)*positions(t,:)+sqrt(dt*D_OU) * v_noise(t,:);
end

speed = sqrt(sum(diff(positions).^2,2));
% Get a smoothed estimate of the speed.
% speed = sqrt(sum(diff(movmean(positions,15)).^2,2));
avgSpeed = mean(speed)*params.frameRate;

% Adjust the values to the indicated speed.
positions = params.motionSpeed*positions/avgSpeed;

% Get the frames for presentation from the end.
positions = positions(end-(ceil(duration*params.frameRate))+1:end,:);
