function check_on_path(host)
% Create a directory for the test
s.work_dir = [cd() '/batch_job_' tmpname() '/'];
mkdir(s.work_dir);
co = onCleanup_(@() rmdir(s.work_dir, 's'));
s.cmd_file = [s.work_dir 'cmd_script.bat'];
s.check_file = [s.work_dir 'check.mat'];

% Save the command script
write_launch_script(sprintf('success = false; try, assert(isequal(batch_job_worker(), ''pass'')); success = true; catch, end; save(''%s'', ''success'');', s.check_file), s.cmd_file);

% Start the worker
start_workers(s, {host, 1});

% Print the host name
if isempty(host)
    host = 'localhost';
end
fprintf('Host: %s. Response: ', host);

% Wait a reasonable amount of time for a response
for a = 1:200
    pause(0.1);
    if ~exist(s.check_file, 'file')
        continue;
    end
    
    % Got a response. Print it out
    s = load(s.check_file);
    if s.success
        fprintf('batch_job_worker() found.\n');
    else
        fprintf('batch_job_worker() NOT found.\n');
    end
    return;
end

% No response
fprintf('none (failed to start worker)\n');
end