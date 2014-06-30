%BATCH_JOB_WORKER Create a batch_job worker
%
%   me = batch_job_worker(job)
%
% This function creates a worker which will attempt to complete jobs posted
% to a particular directory, by either batch_job_distrib() or
% batch_job_submit().
%
%IN:
%   job - full or relative path to the directory where batch jobs are
%         posted, or a filename to a job .mat file if only one job is to be
%         done.
%
%OUT:
%   me - MATLAB exception to an error on the job, if one occurred; []
%        otherwise.

function me = batch_job_worker(job)

% Parse the input
[job_dir, job_file, ext] = fileparts(job);

% Go to the job directory
cd(job_dir);
job_dir = cd(); % Get the absolute path

% Determine if file is given (if so, quit when done)
if ~isempty(job_file) && isequal(lower(ext), '.mat')
    % Do the job
    me = do_job([job_file ext], true);
    return;
end

% The work loop
while 1
    % Get the next job
    d = dir('*.mat');
    
    % Avoid repeating the last job - should really keep a list of
    % completed jobs!
    if ~isempty(d) && isequal(d(1).name, job_file)
        d = d(2:end);
    end
    
    if isempty(d)
        % No new job. Wait for 10 seconds before polling again.
        pause(10);
        continue;
    end
    job_file = d(1).name;

    % Do the job
    do_job(job_file, false);
    
    % Go back to the job directory
    cd(job_dir);
end

