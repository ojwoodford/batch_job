%BATCH_JOB_WORKER Create a batch_job worker
%
%   me = batch_job_worker(job)
%
% This function creates a worker which will attempt to complete jobs posted
% to a particular directory, by either batch_job_distrib() or
% batch_job_submit().
%
% Notes:
%  - The workers need not all run the same operating system, but they must
%    all have working versions of the required functions, including where
%    these are platform-dependent, e.g. mex files.
%
%IN:
%   job - full or relative path to the directory where batch jobs are
%         posted, or a filename to a job .mat file if only one job is to be
%         done.
%
%OUT:
%   me - MATLAB exception to an error on the job, if one occurred; []
%        otherwise.
%
% See also BATCH_JOB_SUBMIT, BATCH_JOB_COLLECT

function me = batch_job_worker(job)
if nargin == 0
    % Testing this function is on the path
    me = 'pass';
    return;
end

% Parse the input
[job_dir, job_file, ext] = fileparts(job);

% Determine if file is given (if so, quit when done)
if isequal(lower(ext), '.mat')
    % Check if we need to set the chunk time
    if exist([job '_'] , 'file')
        % Set the chunk time
        set_chunk_time([job '_']);
    else
        % Do the job
        me = do_job(job, true);
    end
    return;
end

% Go to the job directory
cd(job);
job_dir = cd(); % Get the absolute path

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
end

