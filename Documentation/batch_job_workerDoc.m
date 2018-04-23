%% batch_job_worker
% Create a batch_job worker
%
%% Syntax
%   me = batch_job_worker(job)
%
%% Input Arguments
% * *job* - full or relative path to the directory where batch jobs are
%         posted, or a filename to a job .mat file if only one job is to be
%         done.
%
%% Output Arguments
% * *me* - MATLAB exception to an error on the job, if one occurred; []
%        otherwise.
%
%% Description
% This function creates a worker which will attempt to complete jobs posted
% to a particular directory, by either batch_job_distrib() or
% batch_job_submit().
%
% Notes:
%  * The workers need not all run the same operating system, but they must
%    all have working versions of the required functions, including where
%    these are platform-dependent, e.g. mex files.
%
%% Example
% TODO
%
%% See Also 
% BATCH_JOB_SUBMIT, BATCH_JOB_COLLECT