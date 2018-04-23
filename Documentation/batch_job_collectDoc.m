%% batch_job_collect
% Output data computed by a batch job
%
%% Syntax
%
%   output = batch_job_collect(h)
%
%% Input Arguments
% * *h* - batch job structure created by batch_job_submit.
%
%% Output Arguments
% * *output* - collected output from all the workers, as if the work had been
%            done in a single instance of MATLAB.
%
%% Description
% This function outputs the data computed by batch jobs which have been
% started using:
%
%   h = batch_job_submit(job_dir, func, input, timeout, global_data);
%
% and run on workers running the function:
%
%   batch_job_worker(job_dir);
%
%
%%   See also
% BATCH_JOB_SUBMIT, BATCH_JOB_WORKER, PARFOR