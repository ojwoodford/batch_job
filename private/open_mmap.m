function m = open_mmap(mmap)
 % maps an existing file to memory and returns the memory map, m.
m = memmapfile(mmap.name, 'Format', mmap.format, 'Writable', mmap.writable, 'Repeat', 1);
end

