function [s, mi, func] = setup_job(job)
% Load the job parameters
s = load(job, '-mat');

% CD to the correct directory
cd(s.cwd);

% Get the global data
func = construct_function(s);

% Memory map the indices matrix
mi = open_mmap(s.input_mmap);
