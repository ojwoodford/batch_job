function write_launch_script(funCall, fname)
% Save the command script
cmd = @(str) sprintf('matlab %s -r "try, %s; catch, end; quit force;"', str, funCall);
% Open the file
fh = fopen(fname, 'w');
% Linux bash script
fprintf(fh, ':; nohup /usr/local/bin/%s &\r\n:; exit 0;\r\n', cmd('-nodisplay -nosplash'));
% Windows batch file
fprintf(fh, '@start %s\n', cmd('-automation'));
fclose(fh);
% Make it executable
[status, cmdout] = system(sprintf('chmod u+x "%s"', fname));
assert(status == 0, cmdout);
end