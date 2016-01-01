%BATCH_JOB_SUBMIT Submit a batch job to workers
%
%   batch_job_submit(job_dir, func, input, [timeout, [global_data]])
%
% If you have a for loop which can be written as:
%
%   for a = 1:size(input, 2)
%       output(:,a) = func(input(:,a), global_data);
%   end
%
% where input is a numeric array and output is a numeric or cell array,
% then batch_job_submit() can parallelize the work across multiple worker
% MATLAB instances on multiple (unlimited) networked worker PCs as follows:
%
%   h = batch_job_submit(job_dir, func, input, global_data);
%   output = batch_job_collect(h);
%
% The function can always spread the work across multiple MATLAB workers
% created by running:
%
%   batch_job_worker(job_dir);
%
% in MATLAB on any computer that can see the job_dir directory.
%
% To run successfully in a given instance of MATLAB, the host computer must
%  - Have a valid license for MATLAB and all required toolboxes.
%  - Have write access to the job_dir directory via the SAME path.
%  - Have all required functions on the MATLAB path.
%  - Honour filesystem file locks (not crucial, but safer).
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
%  - There is little point using this function if the for loop would
%    complete in a single MATLAB instance faster than it takes to load the
%    necessary data in another MATLAB instance. As a rule of thumb, if a
%    job will complete in under a minute anyway, do not use this function.
%
%IN:
%   job_dir - path of the directory in which batch jobs are listed.
%   func - a function handle or function name string.
%   input - Mx..xN numeric input data array, to be iterated over the
%           trailing dimension.
%   timeout - a scalar indicating the maximum time (in seconds) to allow
%             one iteration to run for, before killing the calling MATLAB
%             process. If negative, the absolute value is used, but
%             iterations are rerun if they previously timed out; otherwise
%             timed-out iterations are skipped. Default: 0 (no timeout).
%   global_data - a data structure, or function handle or function name
%                 string of a function which returns a data structure, to
%                 be passed to func. Default: global_data not passed to
%                 func.
%
%OUT:
%   h - structure to pass to batch_job_collect() in order to get the
%       results of the parallelization (if there are any).
%
%   See also BATCH_JOB_WORKER, BATCH_JOB_COLLECT, PARFOR

function s = batch_job_submit(job_dir, func, input, timeout, global_data)

% Get the arguments
s.func = func;
if nargin < 4
    timeout = 0;
elseif nargin > 4
    s.global_data = global_data;
end
s.timeout = timeout;

% Get size and reshape data
assert(isnumeric(input));
s.insize = size(input);
s.N = s.insize(end);
s.insize(end) = 1;
input = reshape(input, prod(s.insize), s.N);

% Have at least 10 seconds computation time per chunk, to reduce race
% conditions and improve memory cache efficiency
s.chunk_time = 10;
s.chunk_size = 1;

% Initialize the working directory path
s.cwd = strrep(cd(), '\', '/');
job_dir = strrep(job_dir, '\', '/');
if job_dir(end) == '/'
    job_dir = job_dir(1:end-1);
end
job_name = tmpname();
s.work_dir = [job_dir '/batch_job_' job_name '/'];

% Create a temporary working directory
mkdir(s.work_dir);
s.params_file = [job_dir '/' job_name '.mat'];
% Create the some file names
s.input_mmap.name = [s.work_dir 'input_mmap.dat'];
s.cmd_file = [s.work_dir 'cmd_script.bat'];
% Construct the format
s.input_mmap.format = {class(input), size(input), 'input'};
s.input_mmap.writable = false;

% Create the input data to disk
write_bin(input, s.input_mmap.name);

% Save the command script
write_launch_script(sprintf('batch_job_worker(''%s'')', s.params_file), s.cmd_file);

% If using a timeout, always have a chunk size of one
if s.timeout ~= 0
    % Save the params
    save([s.params_file], '-struct', 's', '-mat');
    return;
end

% Save the params
save([s.params_file '_'], '-struct', 's', '-mat');

try
    % Start a worker to set the chunk time
    [status, cmdout] = system(s.cmd_file);
    assert(status == 0, cmdout);
    
    % Wait for the worker to set the chunk time
    for a = 1:200
        pause(0.1);
        if exist(s.params_file, 'file')
            % Load the new chunk size
            s = load(s.params_file, '-mat');
            fprintf('Chosen chunk size: %d.\n', s.chunk_size);
            return;
        end
    end
catch me
    % Error catching
    fprintf('Could not instantiate worker to set chunk size.\n');
    fprintf('%s\n', getReport(me, 'basic'));
end

% Worker failed or job too long. Assume chunk size of 1 and rename params file
fprintf('Failed to estimate chunk size. Setting to 1.\n');
try
    movefile([s.params_file '_'], s.params_file);
catch
end
