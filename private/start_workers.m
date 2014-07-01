function start_workers(s, workers)
% Start the workers
[p, n, e] = fileparts(s.cmd_file);
[p, p] = fileparts(p);
cmd_file = ['./' p '/' n e];
for w = 1:size(workers, 1)
    if ~isequal(workers{w,1}, '')
        try
            % Copy the command file
            [status, cmdout] = system(sprintf('cat %s | ssh %s "cat - > ./batch_job_distrib_cmd.bat"', cmd_file, workers{w,1}));
            assert(status == 0, cmdout);
            % Make it executable
            [status, cmdout] = system(sprintf('ssh %s "chmod u+x batch_job_distrib_cmd.bat"', workers{w,1}));
            assert(status == 0, cmdout);
        catch me
            % Error catching
            fprintf('Could not copy batch script to host %s\n', workers{w,1});
            fprintf('%s\n', getReport(me, 'basic'));
            continue;
        end
        % Add on the ssh command
        cmd = sprintf('ssh %s ./batch_job_distrib_cmd.bat', workers{w,1});
    else
        cmd = s.cmd_file;
    end
    % Start the required number of MATLAB instances on this host
    for b = 1:workers{w,2}
        try
            [status, cmdout] = system(cmd);
            assert(status == 0, cmdout);
        catch me
            % Error catching
            fprintf('Could not instantiate workers on host %s\n', workers{w,1});
            fprintf('%s\n', getReport(me, 'basic'));
            break;
        end
    end
    if ~isequal(workers{w,1}, '')
        % Remove the command file
        try
            [status, cmdout] = system(sprintf('ssh %s "rm -f ./batch_job_distrib_cmd.bat"', workers{w,1}));
            assert(status == 0, cmdout);
        catch
        end
    end
end
end

