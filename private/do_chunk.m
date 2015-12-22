function ad = do_chunk(func, mi, s, a)
ad = false;
% Get the chunk filename
fname = chunk_name(s.work_dir, a);
% Check if the result file exists
if exist(fname, 'file')
    ad = true; % Mark as already done
    return;
end
% Try to grab the lock for this chunk
[lock, del_lock] = get_file_lock(fname);
if isempty(lock)
    return;
end
% Set the chunk indices
ind = get_chunk_indices(a, s);
% Start a timeout timer if necessary
if s.timeout ~= 0
    ht = timer('StartDelay', abs(s.timeout), 'TimerFcn', @(varargin) kill(del_lock, fname, ind, s));
    start(ht);
end
% Compute the results
for b = numel(ind):-1:1
    try
        output{b} = func(mi.Data.input(:,ind(b)));
    catch me
        output{b} = getReport(me, 'basic');
    end
end
% Stop the timeout timer
if s.timeout ~= 0
    stop(ht);
    delete(ht);
end
% Write out the data
save(fname, 'output', '-v7');
end

function kill(del_lock, fname, ind, s)
if s.timeout > 0
    % Save an empty output
    output = cell(1, numel(ind));
    save(fname, 'output', '-v7');
end
% Delete the lock
del_lock();
% Spawn a new MATLAB instance
start_workers(s, {'', 1});
% Forcibly quit this MATLAB instance
quit('force');
end