Batch Job
=========

A MATLAB toolbox to parallelize simple for loops across multiple MATLAB instances, across multiple computing nodes. For the toolbox to work, its root directory needs to be on your MATLAB path at startup.

### Overview

This toolbox can parallelize for loops which are of the form:
```Matlab
for a = 1:size(input, 2)
    output(:,a) = func(input(:,a), global_data);
end
```
where `input` and `output` can be numeric or cell arrays of any shape or size, and `global_data` can be anything. The for loop iterates over the last non-singleton dimension of `input`, and `output` is concatenated along the first singleton dimension of a single function output.

The for loop is parallelized across multiple MATLAB instances which may or may not be on the same computer, depending on which toolbox function is used.

The for loop is straightforwardly replaced with one or more function calls to batch_job* functions, such as:
```Matlab
output = batch_job_distrib(func, input, {'', num_workers}, global_data);
```
here, `num_workers` being the number of local MATLAB instances to parallelize over.

The functionality in this toolbox essentially replicates that of parfor, without the need for the Parallel Computing Toolbox or a Distributed Computing Server.

In addition, it has some other benefits:
 - Errors are caught and the error message stored, but the for loop continues.
 - The `-progress` option shows a progress bar for the loop.
 - The `-timeout` option allows a timeout to be specified, which limits each iteration to a maximum allowed computation time.
 - The `-async` option allows the loop computation to be done in parallel to other computation in the main thread (`batch_job_distrib()` only).

### Three approaches

The toolbox provides three approaches for parallelizing for loops:
 1. Single call function, `batch_job_distrib()`, which spawns MATLAB instances on the specified computers, and uses the file system to communicate between workers.
 2. Low level functions, `batch_job_submit()` and `batch_job_collect()`, which spread work across worker MATLAB instances (across multiple PCs) which are running `batch_job_worker()`, using the file system to communicate.
 3. Single call function, `batch_job()`, which spawns MATLAB instances locally, and uses a memory mapped file to communicate between workers. This approach does not handle heterogeneous (non-uniform) outputs, nor does support asynchronous computation, but is able to kill more hung processes than `batch_job_distrib()` using the `-timeout` option.

See the help text for each of those functions for usage.

### Reporting bugs

This toolbox has a lot of functionality, and it's difficult to make sure it all works in all scenarios. If you find it's not working for you, please run `batch_job_test()` to make sure that works as expected (i.e. doesn't report any errors). If it does, feel free to report an issue. If it fails, please make sure that the `batch_job` folder is on the path at startup for all workers.
