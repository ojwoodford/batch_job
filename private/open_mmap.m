function m = open_mmap(mmap)
m = memmapfile(mmap.name, 'Format', mmap.format, 'Writable', mmap.writable, 'Repeat', 1);
end

