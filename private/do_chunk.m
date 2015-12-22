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
lock = get_file_lock(fname);
if isempty(lock)
    return;
end
% Set the chunk indices
ind = get_chunk_indices(a, s);
% Start a timeout timer if necessary
if s.timeout > 0
    ht = timer('StartDelay', s.timeout, 'TimerFcn', @(varargin) quit('force'));
    start(ht);
end
% Compute the results
for b = numel(ind):-1:1
    output{b} = func(mi.Data.input(:,ind(b)));
end
% Stop the timeout timer
if s.timeout > 0
    stop(ht);
    delete(ht);
end
% Write out the data
save(fname, 'output', '-v7');
end
