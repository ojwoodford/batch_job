function set_chunk_time(job)
% Do the job initializations
[s, mi, func] = setup_job(job);

% Create a timer to kill MATLAB if first run takes a long time (> 2
% seconds)
ht = timer('StartDelay', 2, 'TimerFcn', @kill);

% Do one instance to work out the size and type of the result, and how long
% it takes
start(ht); % Start the timer to kill if one function evaluation takes too long
tic;
output{1} = func(mi.Data.input(:,1));
t = toc;
stop(ht); % Stop the timer for long function evaluation
delete(ht);

% If the timing is very short, do more evaluations to get a better estimate
% of time per evaluation
if t < 0.5
    s.chunk_size = min(floor(1 / t), s.N);
    tic;
    for a = s.chunk_size:-1:2
        output{a} = func(mi.Data.input(:,a));
    end
    t = toc / (s.chunk_size - 1);
end

% Compute the chunk size
s.chunk_size = min(max(floor(s.chunk_time / t), s.chunk_minmax(1)), s.chunk_minmax(2));

% Save the job file
save(s.params_file, '-struct', 's', '-mat');

% Delete the current one
delete(job);
end

function kill
quit force;
end
