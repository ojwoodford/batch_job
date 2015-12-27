function success = kill_process(pid)
success = false;
if ispc()
    cmd = sprintf('taskkill /f /pid %d', pid);
else
    
    cmd = sprintf('kill -SIGKILL %d', pid);
end
try
    [status, cmdout] = system(cmd);
    assert(status == 0, cmdout);
    success = true;
catch me
    % Error catching
    fprintf('Could not kill process %d.\n', pid);
    fprintf('%s\n', getReport(me, 'basic'));
end
end