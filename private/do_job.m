% Do the job - but catch any errors
function me = do_job(job, kill)
me = [];
try
    % Do the job initializations
    [s, mi, func] = setup_job(job);
    
    if kill
        % Start a timer to check for the kill signal
        ht = timer('ExecutionMode', 'fixedSpacing', 'Period', 2, 'StartDelay', 2, 'Tag', s.work_dir, 'TimerFcn', @kill_signal_t, 'UserData', s);
        start(ht);
    end
    
    % Go over all chunks
    N = ceil(s.N / s.chunk_size);
    ad = false(1, N);
    for a = 1:N
        % Check for the kill signal
        if kill_signal(s)
            break;
        end
        
        % Do the chunk
        ad(a) = do_chunk(func, mi, s, a);
    end
    
    if all(ad)
        % All already done - send the kill signal for this job
        kill_signal(s);
    end
catch me
    % Report the error
    fid = fopen(sprintf('%s.%s.err', job, getComputerName()), 'at');
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
