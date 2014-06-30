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
%   me - MATLAB exception to an error on the last job, if one occurred; []
%        otherwise.

function me = batch_job_worker(job)

% Parse the input
[job_dir, job_file, ext] = fileparts(job);
% Determine if file is given (if so, quit when done)
qwd = ~isempty(job_file) && isequal(lower(ext), '.mat');
if qwd
    job_file = [job_file ext];
else
    job_file = [];
end

% Go to the job directory
cd(job_dir);
job_dir = cd(); % Get the absolute path

% The work loop
while 1
    % Default output
    me = [];
    
    if ~qwd
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
    end
    
    % Do the job - but catch any errors
    try
        % Load the job parameters
        s = load(job_file);
        
        % CD to the correct directory
        cd(s.cwd);
        
        % Get the global data
        s.func_ = construct_function(s);
        
        % Memory map the indices matrix
        s.input_mmap = open_mmap(s.input_mmap);
        
        % Go over all possible chunks in order, starting at a random index
        N = ceil(s.N / s.chunk_size);
        N = circshift(1:N, [0, -floor(rand(1) * N)]);
        for a = N
            % Check for the kill signal
            if kill_signal(s)
                break;
            end
            % Get the chunk filename
            fname = chunk_name(s.work_dir, a);
            % Check if the result file exists
            if exist(fname, 'file')
                continue;
            end
            % Try to grab the lock for this chunk
            lock = get_file_lock(fname);
            if isempty(lock)
                continue;
            end
            % Set the chunk indices
            ind = get_chunk_indices(a, s);
            % Compute the results
            for b = numel(ind):-1:1
                output{b} = s.func_(s.input_mmap.Data.input(:,ind(b)));
            end
            % Write out the data
            save(fname, 'output', '-v7');
            clear lock output
        end
    catch me
        % Report the error
        cd(job_dir);
        fid = fopen(sprintf('%s.%s.err', job_file, getComputerName()), 'at');
        if ~isequal(fid, -1)
            fprintf(fid, '%s\n', getReport(me, 'basic'));
            fclose(fid);
        end
    end
    
    if qwd
        % Quit when done
        return;
    end
    % Clean up stuff
    clear s global_data lock
    % Go back to the job directory
    cd(job_dir);
end

function name = getComputerName()
% GETCOMPUTERNAME returns the name of the computer (hostname)
% name = getComputerName()
%
% WARN: output string is converted to lower case
%
%
% See also SYSTEM, GETENV, ISPC, ISUNIX
%
% m j m a r i n j (AT) y a h o o (DOT) e s
% (c) MJMJ/2007
% MOD: MJMJ/2013

[ret, name] = system('hostname');   
if ret ~= 0,
   if ispc
      name = getenv('COMPUTERNAME');
   else      
      name = getenv('HOSTNAME');      
   end
end
name = strtrim(lower(name));
