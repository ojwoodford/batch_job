%BATCH_JOB_DISTRIB Distribute a MATLAB for loop across several PCs
%
%   output = batch_job_distrib(func, input, [workers, [global_data]], ...)
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
%   '-timeout', timeInSecs - option pair indicating a maximum time to allow
%                            each iteration to run before killing it. 0
%                            means no timeout is used. If non-zero, the
%                            current MATLAB instance is not used to run any
%                            iterations. If negative, the absolute value is
%                            used, but iterations are rerun if they
%                            previously timed out; otherwise timed-out
%                            iterations are skipped. Default: 0 (no
%                            timeout).
%
%OUT:
%   output - Px..xN numeric or cell output array, or if in asynchronous
%            mode, a handle to a function which will return the output
%            array when called (blocking while the batch job finishes, if
%            necessary).
%
%   See also BATCH_JOB_SUBMIT, BATCH_JOB_COLLECT, BATCH_JOB_WORKER, PARFOR

function output = batch_job_distrib(varargin)

% Check for flags
async = false;
progress = false;
keep = false;
timeout = 0;
M = true(size(varargin));
a = 1;
while a <= nargin
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
            case '-timeout'
                a = a + 1;
                timeout = varargin{a};
                assert(isscalar(timeout));
                M(a-1:a) = false;
        end
    end
    a = a + 1;
end
varargin = varargin(M);
progress = progress & usejava('awt');

% Get the arguments
sargs{4} = timeout;
sargs{3} = varargin{2};
sargs{2} = varargin{1};
sargs{1} = cd();
assert(isnumeric(varargin{2}));
N = numel(varargin);
if N > 2 && ~isempty(varargin{3})
    workers = varargin{3};
    assert(iscell(workers) && size(workers, 2) == 2);
else
    workers = {'', feature('numCores')};
end

% Check the worker array makes sense
isposint = @(A) isscalar(A) && isnumeric(A) && round(A) == A && A > 0;
for w = 1:size(workers, 1)
    assert(ischar(workers{w,1}) && isposint(workers{w,2}));
    if isequal(workers{w,1}, '')
        workers{w,2} = workers{w,2} - (~async && timeout == 0); % Start one less if we use this MATLAB instance too
    end
end
if N > 3
    sargs{5} = varargin{4};
end

% Submit the job to the workers
s = batch_job_submit(sargs{:});

% Create the wait bar
hb = [];
if progress
    hb = waitbar(0, 'Starting...', 'Name', 'Batch job processing...');
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

% Make sure the directory gets deleted on exit or if we quit early
co = onCleanup(@() cleanup_all(s, hb, keep, workers));
    
% Start the workers
start_workers(s, workers);

if async
    % Return a handle to the function for getting the output
    output = @() batch_job_collect(s, co);
else
    % Return the output
    output = batch_job_collect(s, co);
end
end

function cleanup_all(s, hb, keep, workers)
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
    kill_signal(s);
    fprintf('Please wait while the workers are halted.\n');
    keep = false;
    % Wait for the workers to stop
    str = [s.work_dir '*.lock'];
    tic;
    while ~isempty(dir(str)) && toc < 4
        pause(0.05);
    end
end
if ~keep
    % Wait for all files to be closed
    pause(0.05);
    % Remove all the other files and the work directory
    rmdir(s.work_dir, 's');
end
% Delete the remote worker scripts
for w = 1:size(workers, 1)
    if ~isequal(workers{w,1}, '')
        % Remove the command file
        try
            [status, cmdout] = system(sprintf('ssh %s "rm -f ./batch_job_distrib_cmd.bat"', workers{w,1}));
            assert(status == 0, cmdout);
        catch me
            % Error catching
            fprintf('Could not delete batch script on host %s\n', workers{w,1});
            fprintf('%s\n', getReport(me, 'basic'));
        end
    end
end
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

