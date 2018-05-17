%% batch_job_submit
% Submit a batch job to workers
%
%% Syntax
%   batch_job_submit(job_dir, func, input)
%   batch_job_submit(job_dir, func, input, timeout)
%   batch_job_submit(job_dir, func, input, timeout, chunk_minmax)
%   batch_job_submit(job_dir, func, input, timeout, chunk_minmax, global_data)
%
%% Input Arguments
% * *job_dir* - path of the directory in which batch jobs are listed.
% * *func* - a function handle or function name string.
% * *input* - size(input) = [..., N]. numeric input data array, to be
%           iterated over the trailing dimension. |input| must be numeric!
%           The last dimenstion corresponds to each iteration |a|,
%           |input(:, a)|. The number of iterations corresponds to size of
%           the last dimension of |input|, N.
%           
% Hint: often it is best to think of |input| as an iterator representing
% the linearIndex (see <matlab:doc('sub2ind') sub2ind>) you want to loop
% over; then |input| is just a vector of indices and
% |global_data.someVariable(a)| corresponds to a value used in |func| at
% iteration |a|.
%
% * *timeout* - a scalar indicating the maximum time (in seconds) to allow
%             one iteration to run for, before killing the calling MATLAB
%             process. If negative, the absolute value is used, but
%             iterations are rerun if they previously timed out; otherwise
%             timed-out iterations are skipped. 
%
%             Default: 0 (no timeout).
%
% * *global_data* - a data structure, or function handle or function name
%                 string of a function which returns a data structure, to
%                 be passed to func. 
%
%             Default: No global data.
%
%% Output Arguments
% * *h* - structure to pass to batch_job_collect() in order to get the
%       results of the parallelization (if there are any).
%
%% Description
% If you have a for loop which can be written as:
%
%   for a = 1:size(input, 2)
%       output(:,a) = func(input(:,a), global_data);
%   end
%
% where input/output is a numeric or cell array, then batch_job_submit() can
% parallelize the work across multiple worker MATLAB instances on multiple
% (unlimited) networked worker PCs as follows:
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
% * Have a valid license for MATLAB and all required toolboxes.
% * Have write access to the job_dir directory via the SAME path.
% * Have all required functions on the MATLAB path.
% * Honour filesystem file locks (not crucial, but safer).
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
% * There is little point using this function if the for loop would
%    complete in a single MATLAB instance faster than it takes to load the
%    necessary data in another MATLAB instance. As a rule of thumb, if a
%    job will complete in under a minute anyway, do not use this function.
%
%% Example
% TODO
%
%% See Also
% BATCH_JOB_WORKER, BATCH_JOB_COLLECT, PARFOR