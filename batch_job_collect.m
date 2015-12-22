%BATCH_JOB_COLLECT Output data computed by a batch job
%
%   output = batch_job_collect(h)
%
% This function outputs the data computed by batch jobs which have been
% started using:
%
%   h = batch_job_submit(job_dir, func, input, timeout, global_data);
%
% and run on workers running the function:
%
%   batch_job_worker(job_dir);
%
%IN:
%   h - batch job structure created by batch_job_submit.
%
%OUT:
%   output - collected output from all the workers, as if the work had been
%            done in a single instance of MATLAB.
%
%   See also BATCH_JOB_SUBMIT, BATCH_JOB_WORKER, PARFOR

function output = batch_job_collect(s, varargin)

% Check if we need to finish up the computation
if exist(s.params_file, 'file')
    % Do the job initializations
    [s, mi, func] = setup_job(s.params_file);
    
    if s.timeout == 0
        % Go over all possible chunks in order, starting at the input index
        chunks_unfinished = true(ceil(s.N / s.chunk_size), 1);
        for a = 1:numel(chunks_unfinished)
            % Do the chunk
            chunks_unfinished(a) = ~do_chunk(func, mi, s, a);
        end
        
        % Wait for all the chunks to finish
        while any(chunks_unfinished)
            % Wait a bit - just to let all the locks be freed
            pause(0.05);
            % Check for the kill signal (user deleted!)
            if kill_signal(s)
                break;
            end
            for a = find(chunks_unfinished)'
                % Get the chunk filename
                fname = chunk_name(s.work_dir, a);
                % Check that the file exists and the lock doesn't
                switch (exist(fname, 'file') ~= 0) * 2 + (exist([fname '.lock'], 'file') ~= 0)
                    case 0
                        % Neither exist (something went wrong!)
                        do_chunk(func, mi, s, a); % Do the chunk now if we can
                        chunks_unfinished(a) = false; % Mark as done regardless
                        % Check for the kill signal
                        if kill_signal(s)
                            break;
                        end
                    case 1
                        % Lock file exists - see if we can grab it
                        lock = get_file_lock(fname, true);
                        % Now delete it
                        clear lock
                    case 2
                        % The mat file exists and the lock doesn't - great
                        chunks_unfinished(a) = false; % Mark as read
                    otherwise
                        % Computation in progress. Go on to the next chunk
                        continue;
                end
            end
        end
    else
        % Wait for the chunks to finish
        chunks_unfinished = true(ceil(s.N / s.chunk_size), 1);
        while any(chunks_unfinished)
            % Wait a bit - just to let all the locks be freed
            pause(0.05);
            % Check for the kill signal (user deleted!)
            if kill_signal(s)
                break;
            end
            % Check the remaining chunks
            for a = find(chunks_unfinished)'
                chunks_unfinished(a) = exist(chunk_name(s.work_dir, a), 'file') == 0;
            end
        end
    end
    clear mi lock func
end

% Tidy up files
d = dir([s.work_dir '*.lock']);
quiet_delete(s.params_file, s.cmd_file, s.input_mmap.name, d(:).name);

% Read in all the outputs
output = cell(s.N, 1);
for a = 1:ceil(s.N / s.chunk_size)
    % Get the chunk filename
    fname = chunk_name(s.work_dir, a);
    % Check that the file exists
    if exist(fname, 'file')
        % Set the chunk indices
        ind = get_chunk_indices(a, s);
        % Read in the data
        output(ind) = getfield(load(fname), 'output');
    end
end
% Reshape the output
output = matrify(output);
end
