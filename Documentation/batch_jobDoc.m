%% batch_job
% Runs a batch job across several instances of MATLAB on the same PC.
%
%% Syntax
%   output = batch_job(func, input)
%   output = batch_job(func, input, global_data)
%   output = batch_job(___, 'Name', Value)
%
%% Input Arguments
% * *func* - a function handle or function name string.
% * *input* - Mx..xN numeric input data array, to be iterated over the
%           trailing dimension.
% * *global_data* - a data structure, function handle, or function name
%                 string of a function which returns a data structure, to
%                 be passed to |func|. Default: |global_data| not passed to
%                 |func|.
%
% *Name-Value Pairs*
%
% * *'-progress', true or false* - flag indicating whether to display a
%                                  progress bar.
% * *'-worker', num_workers* - option pair indicating the number of worker
%                            processes to distribute work over. Default:
%                            feature('numCores').
% * *'-timeout', timeInSecs* - option pair indicating a maximum time to allow
%                            each iteration to run before killing it. 0
%                            means no timeout is used. If non-zero, the
%                            current MATLAB instance is not used to run any
%                            iterations. Timed-out iterations are skipped.
%                            Default: 0 (no timeout).
%
%% Output Arguments
% * *output* - Px..xN numeric output array.
%
%
%% Description
% This is a replacement for parfor in this use case, if you don't have the
% Parallel Computing Toolbox.
%%%
% If you have a for loop which can be written as:
%
%   for a = 1:size(input, 2)
%       output(:,a) = func(input(:,a), global_data);
%   end
%%%
% where both |input| and output are numeric types, then batch_job() can split
% the work across multiple MATLAB instances on the same PC, as follows:
%%%
% The input arguments |func| and |global_data| may optionally be function
% names. When the latter is called, it outputs the true |global_data|. Note
% that |global_data| could be incorporated into |func| before calling
% batch_job, using an anonymous function. The functionality provided here
% simply allows more flexibility. For example, normally every worker loads
% a copy of |global_data| into its own memory space, but this can be avoided
% if |global_data| is a function which loads the data into shared memory via
% a memory mapped file. Indeed, this is the most efficient way of doing
% things - the data doesn't need to be saved to disk first (as it's already
% on the disk), and each worker doesn't store its own copy in memory.
% Passing |global_data| through a function call also allows the function to
% do further initializations, such as setting the path.
%
%% Examples
% * *Independent inputs:*
%
%   for a = 1:size(input, 2)
%       output(:,a) = func(input(:,a));
%   end
%
% becomes:
%
%   output = batch_job(@func, input);
%
% or:
%
%   output = batch_job('func', input);
%%%
% * *Per iteration and global inputs:*
%
%   for a = 1:size(input, 2)
%       output(:,a) = func(input(:,a), global_data);
%   end
%
% becomes:
%
%   output = batch_job(@func, input, global_data);
%
% or:
%
%   output = batch_job('func', input, global_data);
%%%
% * *Per iteration input and global data function:*
%
%   global_data = global_func();
%   for a = 1:size(input, 2)
%       output(:,a) = func(input(:,a), global_data);
%   end
%
% becomes:
%
%   output = batch_job(@func, input, @global_func);
%
% or:
%
%   output = batch_job('func', input, 'global_func');
%
%% See Also 
% <matlab:doc('parfor') parfor> 