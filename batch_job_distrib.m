%batch_job_distrib Distribute a MATLAB for loop across several PCs
%
%   output = batch_job_distrib(func, input)
%   output = batch_job_distrib(func, input, global_data)
%   output = batch_job_distrib(func, input, global_data, workers)
%   output = batch_job_distrib(___, 'Name', Value)
%
%% Input Arguments
% func - a function handle or function name string
% input - Mx..xN numeric input data array, to be iterated over the
%           trailing dimension. input must be numeric!
% global_data - a data structure, function handle, or function name
%                 string of a function which returns a data structure, to
%                 be passed to func. 
%
%  Default: No global_data
%
% workers - Wx2 cell array, with each row being {hostname, num_workers},
%             hostname being a text string indicating the name of a worker
%             PC ('' for the local PC), and num_workers being the number of
%             MATLAB worker instances to start on that PC. 
%
%   Default: {'', feature('numCores')}
%
% Name-Value Pairs:
%
% '-async', true or false - flag indicating to operate in asynchronous.
%                           mode, returning immediately, and completing the
%                           job in the background.
%
%  Default: false
%
% '-progress', true or false - flag indicating to display a progress bar.
%
%  Default: false
%
% '-keep', true or false - flag indicating intermediate result files
%                          should be kept.
%
%  Default: false
%
% '-timeout', timeInSecs - option pair indicating a maximum time to allow
%                          each iteration to run before killing it. 0
%                          means no timeout is used. If non-zero, the
%                          current MATLAB instance is not used to run any
%                          iterations. If negative, the absolute value is
%                          used, but iterations are rerun if they
%                          previously timed out; otherwise timed-out
%                          iterations are skipped. 
%
%  Default: 0 (no timeout)
%
%% Output Arguments
% output - Px..xN numeric array, cell output array, or if in asynchronous
%          mode, a handle to a function which will return the output
%          array when called (blocking while the batch job finishes, if
%          necessary).
%
%% Description
% This is a replacement for parfor if you don't have the Parallel Computing
% Toolbox and/or Distributed Computing Server.
%
% If you have a for loop which can be written as:
%
%   for a = 1:size(input, 2)
%       output(:,a) = func(input(:,a), global_data);
%   end
%
% where input is a numeric array, then batch_job_distrib() can
% parallelize the work across multiple workers. input must be numeric but
% output does not have be the same class as input. output is a cell
% array the same size as input. The work is spread across MATLAB
% instances on multiple (unlimited) networked worker PCs with the following
% command:
%
%   output = batch_job_distrib(func, input, workers, global_data);
%
% There is an asynchronous mode, which returns immediately, passing
% back a handle to a function which can load the output data later:
%
%   output = batch_job_distrib(..., '-async'); % Start an asynchronous computation
%   ...                                        % Do other stuff here
%   output = output();                         % Get the results here
%
% The function can always spread the work across multiple MATLAB instances
% on the local PC, but the requirements for it to run on OTHER PCs are the
% following:
%
% * There is an ssh executable on the system path of the local PC.
% * All worker PCs can be ssh'd into non-interactively (i.e. without
%    manually entering a password).
% * MATLAB is on the system path of all worker PCs.
% * Every worker has a valid license for MATLAB and all required toolboxes
%    for the user ssh'ing in.
% * The current directory can be written to from all worker PCs via the
%    SAME path.
% * All the required functions are on the MATLAB paths of every worker PC.
% * The networked filesystem supports file locks (not crucial, but safer).
% * All the worker PCs honour the networked filesystem file locks (again,
%    not crucial, but safer).
%
% The input arguments func and global_data may optionally be function
% names. When the latter is called, it outputs the true global_data. Note
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
% * The workers need not all run the same operating system, but they must
%    all have working versions of the required functions, including where
%    these are platform-dependent, e.g. mex files.
% * If a single worker uses 100% of CPU due to the code already being
%    parallelized internally, then there is little to be gained by having
%    more than one MATLAB worker instance on each worker PC.
% * There is little point using this function if the for loop would
%    complete in a single MATLAB instance faster than it takes to start a
%    second MATLAB instance and load the necessary data in that instance.
%
%
%% Example
% TODO
%
%   See also BATCH_JOB, BATCH_JOB_SUBMIT, BATCH_JOB_COLLECT, BATCH_JOB_WORKER, PARFOR

function output = batch_job_distrib(func, input, varargin)

%% Input Parsing and Checking

% helper function
getname = @(x) inputname(1);

% Check the input
assert(isnumeric(input),'%s must be numeric.', getname(input));

% Parse the varable input
async = false;
progress = false;
keep = false;
timeout = 0;
global_data = [];
workers = {'', feature('numCores')};
iVar = 1;
while iVar <= length(varargin)
    V = varargin{iVar};
    if ischar(V)
        switch lower(V)
            case '-keep'
                iVar = iVar + 1;
                keep = varargin{iVar};
                assert(islogical(keep),'-keep value must be logical true or false.');
            case '-async'
                iVar = iVar + 1;
                async = varargin{iVar};
                assert(islogical(async),'-async value must be logical true or false.');
            case '-progress'
                iVar = iVar + 1;
                progress = varargin{iVar};
                assert(islogical(progress),'-async value must be logical true or false.');
            case '-timeout'
                iVar = iVar + 1;
                timeout = varargin{iVar};
                assert(isscalar(timeout));
            otherwise
                error('Incorrect Name-Value pair.');
        end
    elseif isstruct(V)
        global_data = V;
    elseif iscell(V)
        workers = V;
        assert(size(workers, 2) == 2, 'workers must have two columns.');
    else
        error('Error in Name-value pairs, global_data, or workers. Cannot parse inputs. Check your input.');
    end
    iVar = iVar + 1;
end

% Check the worker cell array makes sense
isPositiveInteger = @(A) isscalar(A) && isnumeric(A) && round(A) == A && A > 0;
for iWorker = 1:size(workers, 1)
    assert(ischar(workers{iWorker,1}), '%d worker name is not a character array.', iWorker);
    assert(isPositiveInteger(workers{iWorker,2}), 'The number of workers for %d worker name is not a positive integer.', iWorker);
    if isequal(workers{iWorker,1}, '')
        % Start one less if we use this MATLAB instance too
        workers{iWorker,2} = workers{iWorker,2} - (~async && timeout == 0); 
    end
end

%% Do the Work

% Submit the job to the workers
if isempty(global_data)
    s = batch_job_submit(cd(), func, input, timeout);
else
    s = batch_job_submit(cd(), func, input, timeout, global_data);
end

% Check that we can make a waitbar
progress = progress & usejava('awt');

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

%%
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

%%
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
catch
    stop(info.timer);
    delete(info.timer);
end
end

