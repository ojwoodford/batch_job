% Do the job - but catch any errors
function me = do_job(job_file, kill)
me = [];
try
    % Load the job parameters
    s = load(job_file);
    
    if kill
        % Start a timer to check for the kill signal
        ht = timer('ExecutionMode', 'fixedSpacing', 'Period', 2, 'StartDelay', 2, 'Tag', s.work_dir, 'TimerFcn', @kill_signal_t, 'UserData', s);
        start(ht);
    end
    
    % CD to the correct directory
    cd(s.cwd);
    
    % Get the global data
    func = construct_function(s);
    
    % Memory map the indices matrix
    mi = open_mmap(s.input_mmap);
    
    % Go over all possible chunks in order, starting at a random index
    N = ceil(s.N / s.chunk_size);
    N = circshift(1:N, [0, -floor(rand(1) * N)]);
    for a = N
        % Check for the kill signal
        if kill_signal(s)
            break;
        end
        
        % Do the chunk
        do_chunk(func, mi, s, a)
    end
catch me
    % Report the error
    fid = fopen(sprintf('%s.%s.err', job_file, getComputerName()), 'at');
    if ~isequal(fid, -1)
        fprintf(fid, '%s\n', getReport(me, 'basic'));
        fclose(fid);
    end
    if kill
        % Stop timer
        stop(ht);
        delete(ht);
    end
end
if kill
    % Stop timer
    stop(ht);
    delete(ht);
end

function kill_signal_t(ht, varargin)
% Check for the kill signal
if kill_signal(get(ht, 'UserData'))
    quit force; % Stop immediately
end
