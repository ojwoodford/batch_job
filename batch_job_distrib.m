%BATCH_JOB_DISTRIB Distribute a MATLAB for loop across several PCs
%
%   output = batch_job(func, input, [workers, [global_data]])
%
% If you have a for loop which can be written as:
%
%   for a = 1:size(input, 2)
%       output(:,a) = func(input(:,a), global_data);
%   end
%
% where input is a numeric array and output is a numeric or cell array,
% then batch_job_distrib() can parallelize the work across multiple worker
% MATLAB instances on multiple (unlimited) networked worker PCs as follows:
%
%   output = batch_job_distrib(func, input, workers, global_data);
%
% This is a replacement for parfor in this use case, if you don't have the
% Parallel Computing Toolbox and/or Distributed Computing Server.
%
% There is also an asynchronous mode, which returns immediately, passing
% back a handle to a function which can load the output data later:
%
%   output = batch_job_distrib(..., '-async'); % Start an asynchronous computation
%   ...                                        % Do other stuff here
%   output = output();                         % Get the results here
%
% The function can always spread the work across multiple MATLABs on the
% local PC, but the requirements for it to run on OTHER PCs are that:
%  - There is an ssh executable on the system path of the local PC.
%  - All worker PCs can be ssh'd into non-interactively (i.e. without
%    manually entering a password).
%  - MATLAB is on the system path of all worker PCs.
%  - Every worker has a valid license for MATLAB and all required toolboxes
%    for the user ssh'ing in.
%  - The current directory can be written to from all worker PCs via the
%    SAME path.
%  - All the required functions are on the MATLAB paths of every worker PC.
%  - The networked filesystem supports file locks (not crucial, but safer).
%  - All the worker PCs honour the networked filesystem file locks (again,
%    not crucial, but safer).
%
% The input arguments func and global_data may optionally be function
% names. When the latter is called it outputs the true global_data. Note
% that global_data could be incorporated into func before calling
% batch_job, using an anonymous function, but the functionality provided
% here is more flexible. For example, normally every worker loads a copy of
% global_data into its own memory space, but this can be avoided if
% global_data is a function which loads the data into shared memory via a
% memory mapped file. Indeed, this is the most efficient way of doing 
% things - the data doesn't need to be saved to disk first (as it's already
% on the disk), and only one copy is loaded per PC, regardless of the
% number of workers on that PC. Passing global_data through a function call
% also allows the function to do further initializations, such as setting
% the path.
%
% Notes:
%  - The workers need not all run the same operating system, but they must
%    all have working versions of the required functions, including where
%    these are platform-dependent, e.g. mex files.
%  - If a single worker uses 100% of CPU due to the code already being
%    parallelized internally, then there is little to be gained by having
%    more than one MATLAB worker instance on each worker PC.
%  - There is little point using this function if the for loop would
%    complete in a single MATLAB instance faster than it takes to start a
%    second MATLAB instance and load the necessary data in that instance.
%
%IN:
%   func - a function handle or function name string
%   input - Mx..xN numeric input data array, to be iterated over the
%           trailing dimension.
%   workers - Wx2 cell array, with each row being {hostname, num_workers},
%             hostname being a text string indicating the name of a worker
%             PC ('' for the local PC), and num_workers being the number of
%             MATLAB worker instances to start on that PC. Default: {'',
%             feature('numCores')}.
%   global_data - a data structure, or function handle or function name
%                 string of a function which returns a data structure, to
%                 be passed to func. Default: global_data not passed to
%                 func.
%   '-async' - flag indicating to operate in asynchronous mode, returning
%              immediately, and completing the job in the background.
%   '-progress' - flag indicating to display a progress bar.
%   '-keep' - flag indicating intermediate result files should be kept.
%
%OUT:
%   output - Px..xN numeric or cell output array, or if in asynchronous
%            mode, a handle to a function which will return the output
%            array when called (blocking while the batch job finishes, if
%            necessary).
%
%   See also PARFOR

function output = batch_job_distrib(varargin)

isposint = @(A) isscalar(A) && isnumeric(A) && round(A) == A && A > 0;

% Determine if we are a worker
if nargin == 2 && ischar(varargin{1}) && isposint(varargin{2})
    % We are a worker
    % Load the parameters
    s = load(varargin{1});
    % CD to the correct directory
    cd(s.cwd);
    % Construct the function
    func = construct_function(s);
    % Check if we're the principal worker
    if varargin{2} == 0
        % Principal worker - tidy up at the end
        principal_worker(func, s);
    else
        % Normal worker - just loop through chunks
        loop(func, open_mmap(s.input_mmap), s, varargin{2});
    end
    % Quit
    return;
end

% We are the server
% Check for flags
async = false;
progress = false;
keep = false;
M = true(size(varargin));
for a = 1:nargin
    V = varargin{a};
    if ischar(V)
        switch V
            case '-keep'
                keep = true;
                M(a) = false;
            case '-async'
                async = true;
                M(a) = false;
            case '-progress'
                progress = true;
                M(a) = false;
        end
    end
end
varargin = varargin(M);
progress = progress & usejava('awt');
% Get the arguments
s.func = varargin{1};
input = varargin{2};
assert(isnumeric(input));
N = numel(varargin);
if N > 2 && ~isempty(varargin{3})
    workers = varargin{3};
    assert(iscell(workers) && size(workers, 2) == 2);
else
    workers = {'', feature('numCores')};
end
% Check the worker array makes sense
for w = 1:size(workers, 1)
    assert(ischar(workers{w,1}) && isposint(workers{w,2}));
end
if N > 3
    s.global_data = varargin{4};
end
% Get size and reshape data
s.insize = size(input);
s.N = s.insize(end);
s.insize(end) = 1;
input = reshape(input, prod(s.insize), s.N);
% Construct the function
func = construct_function(s);

% Have at least 10 seconds computation time per chunk, to reduce race
% conditions and improve memory cache efficiency
s.chunk_time = 10;
s.chunk_size = 1;

% Initialize the working directory path
s.cwd = strrep(cd(), '\', '/');
s.work_dir = [s.cwd '/batch_job_' tmpname() '/'];

% Create a temporary working directory
mkdir(s.work_dir);
s.params_file = [s.work_dir 'params.mat'];
% Create the some file names
s.input_mmap.name = [s.work_dir 'input_mmap.dat'];
s.cmd_file = [s.work_dir 'cmd_script.bat'];
% Construct the format
s.input_mmap.format = {class(input), size(input), 'input'};
s.input_mmap.writable = false;

% Create the wait bar
hb = [];
if progress
    hb = waitbar(0, 'Starting...', 'Name', 'Batch job processing...');
end

% Make sure the directory gets deleted on exit or if we quit early
co = onCleanup(@() cleanup_all(s, hb, keep));

% Create a timer to start the workers if first run takes a long time
ht = timer('StartDelay', s.chunk_time, 'TimerFcn', @start_workers_t, 'Tag', s.work_dir, 'UserData', {s, input, workers, async, hb});

% Do one instance to work out the size and type of the result, and how long
% it takes
start(ht); % Start the timer to start workers if one function evaluation takes too long
tic;
output = func(input(:,1));
t = toc;
stop(ht); % Stop the timer to start workers if one function evaluation takes too long

% Check if the other workers were started
wnys = get(ht, 'TasksExecuted') == 0;
% Delete the timer
delete(ht);

% Check the output type
assert(isnumeric(output) || iscell(output), 'function output must be a numeric type or cell array');

% Compute the output size and class
outsize = [size(output) s.N];
if outsize(2) == 1
    outsize = outsize([1 3]);
end
outclass = class(output);
output = output(:);

% If the timing is very short, do more evaluations to get a better estimate
% of time per evaluation
if wnys && t < 0.05
    s.chunk_size = min(floor(0.1 / t) + 1, s.N);
    output(:,s.chunk_size) = output;
    tic;
    for a = 2:s.chunk_size
        output(:,a) = reshape(func(input(:,a)), [], 1);
    end
    t = toc / (s.chunk_size - 1);
end

if s.chunk_size == s.N
    % Done already!
    output = reshape(output, outsize);
    if keep
        mkdir(s.work_dir);
        save(output_chunk_filename(s.work_dir, 1), 'output', '-v7');
    end 
    if async
        output = @() output;
    end
    return;
end

if wnys
    % Compute the chunk size
    s.chunk_size = max(floor(s.chunk_time / t), 1);
    
    if s.chunk_size * 2 >= s.N && ~async
        % No point starting workers
        % Just finish up now
        b = size(output, 2);
        output(:,s.N) = output(:,1);
        for a = b+1:s.N
            output(:,a) = reshape(func(input(:,a)), [], 1);
        end
        output = reshape(output, outsize);
        if keep
            mkdir(s.work_dir);
            save(output_chunk_filename(s.work_dir, 1), 'output', '-v7');
        end
        return;
    end
    
    % Start the workers
    start_workers(s, input, workers, async, hb);
else
    % Workers alread started - save the first chunk
    % Get the chunk filename
    fname = output_chunk_filename(s.work_dir, 1);
    % Check if the lock or result file exists
    if ~exist(fname, 'file')
        % Try to grab the lock for this chunk
        lock = get_file_lock(fname);
        if ~isempty(lock)
            % Write out the data
            save(fname, 'output', '-v7');
        end
        clear lock
    end
end
clear output

if async
    % Return a handle to the function for getting the output
    output = @() compute_output(s, outclass, outsize, func, hb, co);
else
    % Return the output
    output = compute_output(s, outclass, outsize, func, hb, co);
end
end

% Start the workers from a timer
function start_workers_t(ht, varargin)
v = get(ht, 'UserData');
start_workers(v{:});
end

function start_workers(s, input, workers, async, hb)
% Check if any workers are needed
if s.N <= 1
    return;
end

% Create the input data to disk
write_bin(input, s.input_mmap.name);

% Save the command script
cmd = @(str, i1) sprintf('matlab %s -r "try, batch_job_distrib(''%s'', %s ); catch, end; quit force;"', str, s.params_file, i1);
% Open the file
fh = fopen(s.cmd_file, 'w');
% Linux bash script
fprintf(fh, ':; nohup %s\rn:; exit\r\n', cmd('-nodisplay -nosplash', '$1'));
% Windows batch file
fprintf(fh, '@start %s\n', cmd('-automation', '%1'));
fclose(fh);

% Save the params
save(s.params_file, '-struct', 's');

% Construct the command string
chunks_per_worker = max(floor(s.N / (s.chunk_size * sum([workers{:,2}]))), 1); % Approximate number of chunks per worker

% Start the progress bar
if ~isempty(hb)
    % Initialize the waitbar data
    info.bar = hb;
    info.time = tic();
    info.dir_str = [s.work_dir 'chunk*.mat'];
    info.nChunks = ceil(s.N / s.chunk_size);
    % Start a timer to update the waitbar
    info.timer = timer('ExecutionMode', 'fixedSpacing', 'Period', 2, 'StartDelay', 2, 'Tag', s.work_dir, 'TimerFcn', @progress_func);
    set(info.timer, 'UserData', info);
    start(info.timer);
end

% Start the other workers
[p, n, e] = fileparts(s.cmd_file);
[p, p] = fileparts(p);
cmd_file = ['./' p '/' n e];
w_ = 1;
for w = 1:size(workers, 1)
    if ~isequal(workers{w,1}, '')
        try
            % Copy the command file
            [status, cmdout] = system(sprintf('cat %s | ssh %s "cat - > ./batch_job_distrib_cmd.bat"', cmd_file, workers{w,1}));
            assert(status == 0, cmdout);
            % Make it executable
            [status, cmdout] = system(sprintf('ssh %s "chmod u+x batch_job_distrib_cmd.bat"', workers{w,1}));
            assert(status == 0, cmdout);
        catch me
            % Error catching
            fprintf('Could not copy batch script to host %s\n', workers{w,1});
            fprintf('%s\n', getReport(me, 'basic'));
            continue;
        end
        % Add on the ssh command
        cmd = @(n) sprintf('ssh %s ./batch_job_distrib_cmd.bat %d', workers{w,1}, n*chunks_per_worker);
    else
        cmd = @(n) sprintf('%s %d', s.cmd_file, n*chunks_per_worker);
        workers{w,2} = workers{w,2} - ~async; % Start one less if we use this MATLAB instance too
    end
    % Start the required number of MATLAB instances on this host
    for b = 1:workers{w,2}
        try
            [status, cmdout] = system(cmd(w_));
            assert(status == 0, cmdout);
            w_ = w_ + 1;
        catch me
            % Error catching
            fprintf('Could not instantiate workers on host %s\n', workers{w,1});
            fprintf('%s\n', getReport(me, 'basic'));
            break;
        end
    end
    if ~isequal(workers{w,1}, '')
        % Remove the command file
        try
            [status, cmdout] = system(sprintf('ssh %s "rm -f ./batch_job_distrib_cmd.bat"', workers{w,1}));
            assert(status == 0, cmdout);
        catch
        end
    end
end
end

function output = compute_output(s, outclass, outsize, func, hb, co)
% co required to ensure cleanup doesn't happen before finished in
% asynchronous case.

if exist(s.params_file, 'file')
    % Finish the work and tidy up
    principal_worker(func, s);
end

% Close the waitbar
try
    close(hb);
catch
end

% Create the output array
outsize(end) = s.N;
if strcmp(outclass, 'cell')
    output = cell([prod(outsize(1:end-1)), outsize(end)]);
else
    output = repmat(cast(NaN, outclass), [prod(outsize(1:end-1)) outsize(end)]);
end

% Read in all the outputs
for a = 1:ceil(s.N / s.chunk_size)
    % Get the chunk filename
    fname = output_chunk_filename(s.work_dir, a);
    % Check that the file exists
    if exist(fname, 'file')
        % Set the chunk indices
        ind = get_chunk_indices(a, s);
        % Read in the data
        output(:,ind) = getfield(load(fname), 'output');
    end
end
% Reshape the output
output = reshape(output, outsize);
end

function principal_worker(func, s)
% Open the memory mapped file
mi = open_mmap(s.input_mmap);

% Start the local worker
loop(func, mi, s, 0);

% Wait for all the chunks to finish
chunks_unfinished = true(ceil(s.N / s.chunk_size), 1);
for b = 1:1e3
    % Check for the kill signal
    if kill_signal(s)
        break;
    end
    for a = find(chunks_unfinished)'
        % Get the chunk filename
        fname = output_chunk_filename(s.work_dir, a);
        % Check that the file exists and the lock doesn't
        switch (exist(fname, 'file') ~= 0) * 2 + (exist([fname '.lock'], 'file') ~= 0)
            case 0
                % Neither exist (something went wrong!)
                do_chunk(func, mi, s, a); % Do the chunk now if we can
                chunks_unfinished(a) = false; % Mark as done regardless
                % Check for the kill signal
                if kill_signal(s)
                    break;
                end
            case 1
                % Lock file exists - see if we can grab it
                lock = get_file_lock(fname, true);
                % Now delete it
                clear lock
            case 2
                % The mat file exists and the lock doesn't - great
                chunks_unfinished(a) = false; % Mark as read
            otherwise
                % Computation in progress. Go on to the next chunk
                continue;
        end
    end
    % Wait a bit - just to let all the locks be freed
    pause(0.05);
    % Check if we're done
    if ~any(chunks_unfinished)
        break;
    end
end

% Tidy up files
clear mi
d = dir([s.work_dir '*.lock']);
quiet_delete(s.params_file, s.cmd_file, s.input_mmap.name, d(:).name);
end

function write_bin(A, fname)
assert(isnumeric(A), 'Exporting non-numeric variables not supported');
assert(isreal(A), 'Exporting complex numbers not tested');
fh = fopen(fname, 'w', 'n');
if fh == -1
    error('Could not open file %s for writing.', fname);
end
fwrite(fh, A, class(A));
fclose(fh);
end

function nm = tmpname()
[nm, nm] = fileparts(tempname());
end

function m = open_mmap(mmap)
m = memmapfile(mmap.name, 'Format', mmap.format, 'Writable', mmap.writable, 'Repeat', 1);
end

function func = construct_function(s)
% Get the global data
if isfield(s, 'global_data')
    try
        % Try to load from a function
        global_data = feval(s.global_data);
    catch
        global_data = s.global_data;
    end
    % Get the function handle
    func = @(A) feval(s.func, reshape(A, s.insize), global_data);
else
    func = @(A) feval(s.func, reshape(A, s.insize));
end
end

function loop(func, mi, s, shift)
% Start a timer to check for the kill signal
if shift ~= 0
    ht = timer('ExecutionMode', 'fixedSpacing', 'Period', 2, 'StartDelay', 2, 'Tag', s.work_dir, 'TimerFcn', @kill_signal_t, 'UserData', s);
    start(ht);
end
% Go over all possible chunks in order, starting at the input index
for a = circshift(1:ceil(s.N / s.chunk_size), [1, -shift])
    % Do the chunk
    if do_chunk(func, mi, s, a)
        break; % Error, so quit
    end
end
% Stop the kill signal timer
if shift ~= 0
    stop(ht);
    delete(ht);
end
end

function br = do_chunk(func, mi, s, a)
br = false;
try
    % Get the chunk filename
    fname = output_chunk_filename(s.work_dir, a);
    % Check if the result file exists
    if exist(fname, 'file')
        return;
    end
    % Try to grab the lock for this chunk
    lock = get_file_lock(fname);
    if isempty(lock)
        return;
    end
    % Set the chunk indices
    ind = get_chunk_indices(a, s);
    % Compute the results
    for b = numel(ind):-1:1
        output(:,b) = reshape(func(mi.Data.input(:,ind(b))), [], 1);
    end
    % Write out the data
    save(fname, 'output', '-v7');
catch me
    % Report the error
    fprintf('%s\n', getReport(me, 'basic'));
    % Quit
    br = true;
end
end

function fname = output_chunk_filename(work_dir, ind)
fname = sprintf('%schunk%6.6d.mat', work_dir, ind);
end

function ind = get_chunk_indices(a, s)
ind = (a-1)*s.chunk_size+1:min(a*s.chunk_size, s.N);
end

function quiet_delete(varargin)
for fname = varargin
    if exist(fname{1}, 'file')
        delete(fname{1});
    end
end
end

function cleanup_all(s, hb, keep)
% Stop any timers
ht = timerfindall('Tag', s.work_dir);
for a = 1:numel(ht)
    stop(ht(a));
    delete(ht(a));
end
% Close the waitbar
try
    close(hb);
catch
end
% Check if we need to send the kill signal
if ~kill_signal(s)
    % Send the signal
    fprintf('Please wait while the workers are halted.\n');
    delete(s.params_file);
    % Wait for the workers to stop
    str = [s.work_dir '*.lock'];
    tic;
    while ~isempty(dir(str)) && toc < 4
        pause(0.05);
    end
    pause(0.05);
    % Remove all the other files and the work directory
    rmdir(s.work_dir, 's');
elseif ~keep
    % Remove all the other files and the work directory
    rmdir(s.work_dir, 's');
end
end

function kill_signal_t(ht, varargin)
% Check for the kill signal
if kill_signal(get(ht, 'UserData'))
    quit force; % Stop immediately
end
end

function tf = kill_signal(s)
% Signalled if the params file is deleted
tf = exist(s.params_file, 'file') == 0;
end

function progress_func(ht, varargin)
% Get the progress bar info
info = get(ht, 'UserData');
% Compute the proportion finished
proportion = numel(dir(info.dir_str)) / info.nChunks;
% Check if done
if proportion >= 1
    stop(info.timer);
    delete(info.timer);
    close(info.bar);
    drawnow;
    return;
end
% Update the title
t_elapsed = toc(info.time);
t_remaining = ((1 - proportion) * t_elapsed) / proportion;
newtitle = sprintf('Elapsed: %s', timestr(t_elapsed));
if proportion > 0.01 || (t_elapsed > 30 && proportion ~= 0)
    if t_remaining < 600
        newtitle = sprintf('%s, Remaining: %s', newtitle, timestr(t_remaining));
    else
        newtitle = sprintf('%s, ETA: %s', newtitle, datestr(datenum(clock()) + (t_remaining * 1.15741e-5), 0));
    end
end
% Protect against the waitbar being closed
try
    waitbar(proportion, info.bar, newtitle);
catch me
    stop(info.timer);
    delete(info.timer);
end
end

% Time string function
function str = timestr(t)
s = rem(t, 60);
m = rem(floor(t/60), 60);
h = floor(t/3600);

if h > 0
    str= sprintf('%dh%02dm%02.0fs', h, m, s);
elseif m > 0
    str = sprintf('%dm%02.0fs', m, s);
else
    str = sprintf('%2.1fs', s);
end
end
