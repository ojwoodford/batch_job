%BATCH_JOB Run a batch job across several instances of MATLAB on the same PC
%
%% Syntax
%   output = batch_job(func, input)
%   output = batch_job(func, input, global_data)
%   output = batch_job(___, optionOrFlag)
%
%% Input Arguments
% * *func* - a function handle or function name string.
% * *input* - Mx..xN numeric input data array, to be iterated over the
%           trailing dimension.
% * *global_data* - a data structure, function handle, or function name
%                 string of a function which returns a data structure, to
%                 be passed to |func|. 
%
%  Default: No global_data
%
% *Options and flags*
%
% * *'-progress'* - flag indicating whether to display a progress bar. 
%                   
% * *'-workers', num_workers* - option pair indicating the number of worker
%                            processes to distribute work over. 
%
%   Default: feature('numCores')
%
% * *'-timeout', timeInSecs* - option pair indicating a maximum time to allow
%                            each iteration to run before killing it. 0
%                            means no timeout is used. If non-zero, the
%                            current MATLAB instance is not used to run any
%                            iterations. Timed-out iterations are skipped.
%
%   Default: 0 (no timeout)
%
%% Output Arguments
% * *output* - Px..xN numeric output array.
%
%% Description
% This is a replacement for parfor in this use case, if you don't have the
% Parallel Computing Toolbox.
%
% If you have a for loop which can be written as:
%
%   for a = 1:size(input, 2)
%       output(:,a) = func(input(:,a), global_data);
%   end
%
% where both input and output are numeric types, then batch_job() can split
% the work across multiple MATLAB instances on the same PC, as follows:
%
% The input arguments func and global_data may optionally be function
% names. When the latter is called, it outputs the true global_data. Note
% that global_data could be incorporated into func before calling
% batch_job, using an anonymous function. The functionality provided here
% simply allows more flexibility. For example, normally every worker loads
% a copy of global_data into its own memory space, but this can be avoided
% if global_data is a function which loads the data into shared memory via
% a memory mapped file. Indeed, this is the most efficient way of doing
% things - the data doesn't need to be saved to disk first (as it's already
% on the disk), and each worker doesn't store its own copy in memory.
% Passing global_data through a function call also allows the function to
% do further initializations, such as setting the path.
%
%% Examples:
% 1. Independent inputs:
%
%   for a = 1:size(input, 2)
%       output(:,a) = func(input(:,a));
%   end
%
% becomes:
%   output = batch_job(@func, input);
% or:
%   output = batch_job('func', input);
%
% 2. Per iteration and global inputs:
%
%   for a = 1:size(input, 2)
%       output(:,a) = func(input(:,a), global_data);
%   end
%
% becomes:
%   output = batch_job(@func, input, global_data);
% or:
%   output = batch_job('func', input, global_data);
%
% 3. Per iteration input and global data function:
%
%   global_data = global_func();
%   for a = 1:size(input, 2)
%       output(:,a) = func(input(:,a), global_data);
%   end
%
% becomes:
%   output = batch_job(@func, input, @global_func);
% or:
%   output = batch_job('func', input, 'global_func');
%
%
%   See also PARFOR

function output = batch_job(func, input, varargin)


%% Determine if we are a worker
% function to check for a positive, scalar integer
isposint = @(A) isscalar(A) && isnumeric(A) && round(A) == A && A > 0;
if nargin == 2 && ischar(func) && isposint(input)
    % We are a worker
    worker = input;
    % Load the first two parameters
    s = load(func, 'cwd', 'output_mmap');
    % CD to the correct directory
    cd(s.cwd);
    % Open the output file
    mo = open_mmap(s.output_mmap);
    try
        % Load all the parameters
        s = load(func);
        % Open the input data file
        mi = open_mmap(s.input_mmap);
        % Register the process id
        mo.Data.PID(worker) = feature('getpid');
        % Construct the function
        func = construct_function(s);
    catch me
        % Flag as done
        mo.Data.finished(worker) = 1;
        % Error catching
        fprintf('Could not initialise worker %d.\n', worker);
        fprintf('%s\n', getReport(me, 'basic'));
        return;
    end
    % Work until there is no more data
    worker_loop(func, mi, mo, s, worker);
    % Quit
    return;
end

%% We are the Server
% Check for flags
num_workers = feature('numCores');
progress = false;
timeout = 0;
global_data = [];
iVar = 1;
while iVar <= length(varargin)
    V = varargin{iVar};
    if ischar(V)
        switch lower(V)
            case '-workers'
                iVar = iVar + 1;
                num_workers = varargin{iVar};
                 assert(isposint(num_workers), 'num_workers should be a positive integer.');
            case '-progress'
                progress = true;
            case '-timeout'
                iVar = iVar + 1;
                timeout = varargin{iVar};
                assert(isscalar(timeout));
            otherwise
                 error('Incorrect option or flag pair: %s', varargin{iVar});
        end
    elseif isstruct(V)
        global_data = V;
    else
        error('Error in option, flag, global_data, or num_workers. Cannot parse inputs. Check your input.');
    end
    iVar = iVar + 1;
end

s.progress = progress & usejava('awt');
s.timeout = timeout / (24 * 60 * 60); % Convert from seconds to days
use_local = timeout == 0;


%% Do Work

% Get the arguments
s.func = func;
if ~isempty(global_data)
    s.global_data = global_data;
end

% Get size and reshape data
s.insize = size(input);
N = s.insize(end);
s.insize(end) = 1;
input = reshape(input, prod(s.insize), N);
% Construct the function
func = construct_function(s);

% Do one instance to work out the size and type of the result, and how long
% it takes 
tic;
output = func(reshape(input(:,1), s.insize));
t = toc;
if timeout ~= 0
    t = Inf;
end

% Check output
assert(isnumeric(output), 'func output must be a numeric type.');

% Compute the output size
outsize = [size(output) N];
if outsize(2) == 1
    outsize = outsize([1 3]);
end

% Have at least 10 seconds computation time per chunk, to reduce race
% conditions
s.chunk_size = max(ceil(10 / t), 1);
fprintf('Chosen chunk size: %d.\n', s.chunk_size);
num_workers = min(ceil(N / s.chunk_size), num_workers);

% Create a temporary working directory
s.cwd = strrep(cd(), '\', '/');
s.work_dir = [strrep(fullfile(s.cwd, ['batch_job_' tmpname()]), '\', '/'), '/'];
mkdir(s.work_dir);
% Make sure the directory gets deleted on exit
co = onCleanup(@() rmdir(s.work_dir, 's')); % Comment out this line if you want to keep all files for debugging

% Create the files to be memory mapped
% Create the filenames
s.input_mmap.name = [s.work_dir 'input_mmap.dat'];
s.output_mmap.name = [s.work_dir 'output_mmap.dat'];
% Create the files on disk
write_bin(input, s.input_mmap.name);
preallocate_file(s.output_mmap.name, 4 + num_workers * 13 + num_bytes(output) * N);
% Construct the formats
s.input_mmap.format = {class(input), size(input), 'input'};
s.input_mmap.writable = false;
s.output_mmap.format = {'uint32', [1 1], 'index'; ...
                        'uint8', [num_workers 1], 'finished'; ...
                        'uint32', [num_workers 1], 'PID'; ...
                        'double', [num_workers 1], 'timeout'; ...
                        class(output), [numel(output) N], 'output'};
s.output_mmap.writable = true;

% Save the params
s.params_file = [s.work_dir 'params.mat'];
save(s.params_file, '-struct', 's');

% Open the memory mapped files
mi = open_mmap(s.input_mmap);
mo = open_mmap(s.output_mmap);

% Set the data
mo.Data.index = uint32(2);
mo.Data.timeout(:) = Inf;
mo.Data.finished(:) = 0;
mo.Data.output(:,1) = output(:);
mo.Data.output(:,2:end) = NaN;

% Start the other workers
workers_started = 0;
for worker = 1+use_local:num_workers
    if ~start_worker(worker, s.params_file)
        break;
    end
    workers_started = workers_started + 1;
end

if use_local
    % Start the local worker
    local_loop(func, mi, mo, s);
else
    assert(workers_started > 0, 'No workers were successfully started');
    % Wait until finished
    idle_loop(mo, s);
end

% Get the output
output = reshape(mo.Data.output, outsize);
end

%%
function worker_loop(func, mi, mo, s, worker)
% Initialize values
N = size(mi.Data.input, 2);
n = uint32(s.chunk_size);
% Continue until there is no more data to get
while 1
    % Get and increment the current index - assume this is atomic!
    ind = mo.Data.index;
    mo.Data.index = ind + n;
    % Check that there is stuff to be done
    ind = double(ind);
    if ind > N
        % Nothing left to do, so quit
        break;
    end
    % Do a chunk
    for a = ind:min(ind+n-1, N)
        % Set the timeout time
        mo.Data.timeout(worker) = now() + s.timeout;
        % Compute the results
        try
            mo.Data.output(:,a) = reshape(func(mi.Data.input(:,a)), [], 1);
        catch
        end
    end
    % Disable the timeout
    mo.Data.timeout(worker) = Inf;
end
% Flag as finished
mo.Data.finished(worker) = 1;
end

%%
function local_loop(func, mi, mo, s)
% Initialize values
N = size(mi.Data.input, 2);
n = uint32(s.chunk_size);
if s.progress
    % Create progress function
    info.start_prop = double(mo.Data.index) / N;
    info.bar = waitbar(info.start_prop, 'Starting...', 'Name', 'Batch job processing...');
    info.timer = tic();
    progress = @(v) progressbar(info, v);
else
    progress = @(v) v;
end
% Continue until there is no more data to get
while 1
    % Get and increment the current index - assume this is atomic!
    ind = mo.Data.index;
    mo.Data.index = ind + n;
    % Check that there is stuff to be done
    ind = double(ind);
    if ind > N
        % Nothing left to do, so quit
        break;
    end
    % Do a chunk
    for a = ind:min(ind+n-1, N)
        % Compute the results
        mo.Data.output(:,a) = reshape(func(mi.Data.input(:,a)), [], 1);
    end
    % Display progress and other bits
    progress(ind/N);
end
% Flag as finished
mo.Data.finished(1) = 1;
progress(1);
% Wait for all the workers to finish
while ~all(mo.Data.finished)
    pause(0.01);
end
end

%%
function idle_loop(mo, s)
% Initialize progress bar
N = size(mo.Data.output, 2);
if s.progress
    % Create progress function
    info.start_prop = double(mo.Data.index) / N;
    info.bar = waitbar(info.start_prop, 'Starting...', 'Name', 'Batch job processing...');
    info.timer = tic();
    progress = @(v) progressbar(info, v);
else
    progress = @(v) v;
end
% Continue until finished
while ~all(mo.Data.finished)
    pause(0.05);
    % Display progress
    ind = mo.Data.index;
    progress(ind/N);
    % Check for timed-out processes
    for worker = 1:numel(mo.Data.timeout)
        if mo.Data.timeout(worker) > now()
            continue;
        end
        %fprintf('Restarting worker %d.\n', worker);
        % Kill the process
        kill_process(mo.Data.PID(worker));
        % Set the timeout to infinity
        mo.Data.timeout(worker) = Inf;
        % Start a new process
        start_worker(worker, s.params_file);
    end
end
progress(1);
end

%%
function progressbar(info, proportion)
% Protect against the waitbar being closed
try
    if proportion >= 1
        close(info.bar);
        drawnow();
        return;
    end
    t_elapsed = toc(info.timer);
    t_remaining = ((1 - proportion) * t_elapsed) / (proportion - info.start_prop);
    newtitle = sprintf('Elapsed: %s', timestr(t_elapsed));
    if proportion > 0.01 || t_elapsed > 30
        if t_remaining < 600
            newtitle = sprintf('%s, Remaining: %s', newtitle, timestr(t_remaining));
        else
            newtitle = sprintf('%s, ETA: %s', newtitle, datestr(datenum(clock()) + (t_remaining * 1.15741e-5), 0));
        end
    end
    waitbar(proportion, info.bar, newtitle);
    drawnow();
catch
end
end

%%
function success = start_worker(worker, params_file)
success = false;
if ispc()
    executable = 'matlab';
else
    executable = '/usr/local/bin/matlab';
end
try
       
    [status, cmdout] = system(sprintf('%s -automation -nodisplay -r "try, batch_job(''%s'', %d); catch, end; quit();" &', executable, params_file, worker));

    % debug line
%     [status, cmdout] = system(sprintf('%s -desktop -r "fprintf(''Worker %d\\n''), try, batch_job(''%s'', %d); catch, end;" &', executable, worker, params_file, worker));
    assert(status == 0, cmdout);
    success = true;
catch me
    % Error catching
    fprintf('Could not instantiate worker.\n');
    fprintf('%s\n', getReport(me, 'basic'));
end
end
