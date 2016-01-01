function [s, mi, func] = setup_job(job)
% CD to the correct directory
s = load(job, '-mat', 'cwd');
cd(s.cwd);

% Load the job parameters
s = load(job, '-mat');

% Get the global data
func = construct_function(s);

% Memory map the indices matrix
mi = open_mmap(s.input_mmap);