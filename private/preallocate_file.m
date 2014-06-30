function preallocate_file(name, nbytes)
fh = javaObject('java.io.RandomAccessFile', name, 'rw');
% Allocate the right amount of space
fh.setLength(nbytes);
% Close the file
fh.close();
end
