function ind = get_chunk_indices(a, s)
ind = (a-1)*s.chunk_size+1:min(a*s.chunk_size, s.N);
end
