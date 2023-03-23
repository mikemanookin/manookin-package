function positions = getHMMTrajectory2d(duration, seed, varargin)

ip = inputParser();
ip.addParameter('correlationDecayTau', 20, @(x)isfloat(x));
ip.addParameter('frameRate', 60.0, @(x)isfloat(x));
ip.addParameter('motionSpeed', 700.0, @(x)isfloat(x)); % Motion speed in pixels / sec

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
positionStream = RandStream('mt19937ar', 'Seed', seed);

D_HMM = 2.7e6; %dynamical range
omega = params.correlationDecayTau/2.12;   % omega = G/(2w)=1.06; follow Bielak's overdamped dynamics/ 2015PNAS

% Get your position vector (x,y).
positions = zeros(length(T), 2);
% Velocity vectors (x,y)
V = zeros(length(T), 2);
v_noise = positionStream.randn(length(T), 2);

% Update the velocities and positions on each time step according to the
% HMM algorithm.
for t = 1 : length(T)-1
    positions(t+1,:) = positions(t,:) + V(t,:)*dt;
    V(t+1,:) = (1-params.correlationDecayTau*dt)*V(t,:) - omega^2*positions(t,:)*dt + sqrt(dt*D_HMM)*v_noise(t,:);
end

speed = sqrt(sum(diff(positions).^2,2));
% Get a smoothed estimate of the speed.
% speed = sqrt(sum(diff(movmean(positions,15)).^2,2));
avgSpeed = mean(speed)*params.frameRate;

% Adjust the values to the indicated speed.
positions = params.motionSpeed*positions/avgSpeed;

% Get the frames for presentation from the end.
positions = positions(end-(ceil(duration*params.frameRate))+1:end,:);
