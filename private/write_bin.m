function write_bin(A, fname)
assert(isnumeric(A), 'Exporting non-numeric variables not supported');
assert(isreal(A), 'Exporting complex numbers not tested');
fh = fopen(fname, 'w', 'n');
if fh == -1
    error('Could not open file %s for writing.', fname);
end
fwrite(fh, A, class(A));
fclose(fh);
end
