%% batch_job_distrib
% Distribute a MATLAB for loop across several PCs
%
%% Syntax
%   output = batch_job_distrib(func, input)
%   output = batch_job_distrib(func, input, global_data)
%   output = batch_job_distrib(func, input, global_data, workers)
%   output = batch_job_distrib(___, optionOrFlag)
%
%% Input Arguments
% * *func* - a function handle or function name string
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
% * *global_data* - a data structure, function handle, or function name
%                 string of a function which returns a data structure, to
%                 be passed to |func|.
%
%  Default: No global_data
%
% * *workers* - Wx2 cell array, with each row being {hostname, num_workers},
%             hostname being a text string indicating the name of a worker
%             PC (|''| for the local PC), and num_workers being the number of
%             MATLAB worker instances to start on that PC. 
%
%   Default: {'', feature('numCores')}
%
% *Options and flags*
%
% * *'-async'* - flag indicating to operate in asynchronous.
% mode, returning immediately, and completing the job in the background.
%
% * *'-progress'* - flag indicating to display a progress bar.
%
% * *'-keep'* - flag indicating intermediate result files should be kept.
%
% * *'-timeout', timeInSecs* - option pair indicating a maximum time to allow
%                            each iteration to run before killing it. 0
%                            means no timeout is used. If non-zero, the
%                            current MATLAB instance is not used to run any
%                            iterations. If negative, the absolute value is
%                            used, but iterations are rerun if they
%                            previously timed out; otherwise timed-out
%                            iterations are skipped. 
%
%  Default: 0 (no timeout)
%
%% Output Arguments
% * *output* - Px..xN. numeric array, cell output array, or if in asynchronous
%            mode, a handle to a function which will return the output
%            array when called (blocking while the batch job finishes, if
%            necessary). Each column corresponds to an iteration |a|,
%            |output(:,a)|.
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
% where |input| is a numeric array, then batch_job_distrib() can
% parallelize the work across multiple workers. |input| must be numeric but
% |output| does not have be the same class as |input|. |output| is a cell
% array the same size as |input|. The work is spread across MATLAB
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
% The input arguments |func| and |global_data| may optionally be function
% names. When the latter is called, it outputs the true |global_data|. Note
% that global_data could be incorporated into |func| before calling
% batch_job, using an anonymous function, but the functionality provided
% here is more flexible. For example, normally every worker loads a copy of
% global_data into its own memory space, but this can be avoided if
% global_data is a function which loads the data into shared memory via a
% memory mapped file. Indeed, this is the most efficient way of doing 
% things - the data doesn't need to be saved to disk first (as it's already
% on the disk), and only one copy is loaded per PC, regardless of the
% number of |workers| on that PC. Passing global_data through a function call
% also allows the function to do further initializations, such as setting
% the path.
%
% Notes:
%
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
%% Example
% TODO
%
%% See Also 
% <matlab:web('batch_jobDoc.html') batch_job>, batch_job_submit, batch_job_collect, batch_job_worker, 