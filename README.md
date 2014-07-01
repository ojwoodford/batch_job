Batch Job
=========

A MATLAB toolbox to parallelize simple for loops across multiple MATLAB instances, across multpile computing nodes.

### Overview

This toolbox can parallelize for loops which are of the form:
```Matlab
for a = 1:size(input, 2) 
    output(:,a) = func(input(:,a), global_data); 
end
```
where `input` and `output` can be numeric or cell arrays of any shape or size, and `global_data` can be anything. The for loop iterates over the last non-singleton dimension of `input`, and `output` is concatenated along the first singleton dimension of a single function output.

The for loop is parallelized across multiple MATLAB instances which may or may not be on the same computer, depending on which toolbox function is used.

The for loop is straightfowardly replaced with one or more function calls to batch_job* functions, such as:
```Matlab
output = batch_job(func, input, num_workers, global_data);
```
here, `num_workers` being the number of local MATLAB instances to parallelize over.

The functionality in this toolbox essentially replicates that of parfor, without the need for the Parallel Computing Toolbox or a Distributed Computing Server.

### Three approaches

The toolbox provides three approaches for parallelizing for loops:
 1. Single call function, batch_job(), which spawns MATLAB instances locally, and uses a memory mapped file to communicate between workers.
 2. Single call function, batch_job_distrib(), which spawns MATLAB instances on the specified computers, and uses the file system to communicate between workers.
 3. Low level functions, batch_job_submit() and batch_job_collect(), which spread work across worker MATLAB instances (across multiple PCs) which are running batch_job_worker(), using the file system to communicate.

See the help text for each of those functions for usage.
