function do_chunk(func, mi, s, a)
% Get the chunk filename
fname = chunk_name(s.work_dir, a);
% Check if the result file exists
if exist(fname, 'file')
    return;
end
% Try to grab the lock for this chunk
lock = get_file_lock(fname);
if isempty(lock)
    return;
end
% Set the chunk indices
ind = get_chunk_indices(a, s);
% Compute the results
for b = numel(ind):-1:1
    output{b} = func(mi.Data.input(:,ind(b)));
end
% Write out the data
save(fname, 'output', '-v7');
end
