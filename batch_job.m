%BATCH_JOB Run a batch job across several instances of MATLAB on the same PC
%
%   output = batch_job(func, input, [num_workers, [global_data]])
%
% If you have a for loop which can be written as:
%
%   for a = 1:size(input, 2)
%       output(:,a) = func(input(:,a), global_data);
%   end
%
% where both input and output are numeric types, then batch_job() can split
% the work across multiple MATLAB instances on the same PC, as follows:
%
%   output = batch_job(func, input, 4, global_data);
%
% This is a replacement for parfor in this use case, if you don't have the
% Parallel Computing Toolbox.
%
% The input arguments func and global_data may optionally be function
% names. When the latter is called it outputs the true global_data. Note
% that global_data could be incorporated into func before calling
% batch_job, using an anonymous function. The functionality provided here
% simply allows more flexibility. For example, normally every worker loads
% a copy of global_data into its own memory space, but this can be avoided
% if global_data is a function which loads the data into shared memory via
% a memory mapped file. Indeed, this is the most efficient way of doing
% things - the data doesn't need to be saved to disk first (as it's already
% on the disk), and each worker doesn't store its own copy in memory.
% Passing global_data through a function call also allows the function to
% do further initializations, such as setting the path.
%
%IN:
%   func - a function handle or function name string
%   input - Mx..xN numeric input data array, to be iterated over the
%           trailing dimension.
%   num_workers - number of worker processes to distribute work over.
%                 Default: feature('numCores').
%   global_data - a data structure, or function handle or function name
%                 string of a function which returns a data structure, to
%                 be passed to func. Default: global_data not passed to
%                 func.
%
%OUT:
%   output - Px..xN numeric output array.
%
%   See also PARFOR

function output = batch_job(varargin)

isposint = @(A) isscalar(A) && isnumeric(A) && round(A) == A && A > 0;

% Determine if we are a worker
if nargin == 2 && ischar(varargin{1}) && isposint(varargin{2})
    % We are a worker
    % Load the parameters
    s = load(varargin{1});
    % CD to the correct directory
    cd(s.cwd);
    % Open the memory mapped files
    mi = open_mmap(s.input_mmap);
    mo = open_mmap(s.output_mmap);
    % Construct the function
    func = construct_function(s);
    % Work until there is no more data
    loop(func, mi, mo, s.chunk_size, varargin{2});
    % Quit
    return;
end

% We are the server
% Get the arguments
s.func = varargin{1};
input = varargin{2};
assert(isnumeric(input));
if nargin > 2
    assert(isposint(varargin{3}), 'num_workers should be a positive integer');
    num_workers = varargin{3};
else
    num_workers = feature('numCores');
end
if nargin > 3
    s.global_data = varargin{4};
end
% Get size and reshape data
s.insize = size(input);
N = s.insize(end);
s.insize(end) = 1;
input = reshape(input, prod(s.insize), N);
% Construct the function
func = construct_function(s);

% Do one instance to work out the size and type of the result, and how long
% it takes 
tic;
output = func(reshape(input(:,1), s.insize));
t = toc;
assert(isnumeric(output), 'function output must be a numeric type');
% Compute the output size
outsize = [size(output) N];
if outsize(2) == 1
    outsize = outsize([1 3]);
end

% Have at least 10 seconds computation time per chunk, to reduce race
% conditions
s.chunk_size = max(ceil(10 / t), 1);
num_workers = min(ceil(N / s.chunk_size), num_workers);

% Create a temporary working directory
s.cwd = cd();
s.work_dir = [s.cwd filesep 'batch_job_' tmpname() filesep];
mkdir(s.work_dir);
% Make sure the directory gets deleted on exit
co = onCleanup(@() rmdir(s.work_dir, 's')); % Comment out this line if you want to keep all files for debugging

% Create the files to be memory mapped
% Create the filenames
s.input_mmap.name = [s.work_dir 'input_mmap.dat'];
s.output_mmap.name = [s.work_dir 'output_mmap.dat'];
% Create the files on disk
write_bin(input, s.input_mmap.name);
preallocate_file(s.output_mmap.name, 4 + num_workers + num_bytes(output) * N);
% Construct the formats
s.input_mmap.format = {class(input), size(input), 'input'};
s.input_mmap.writable = false;
s.output_mmap.format = {'uint32', [1 1], 'index'; 'uint8', [num_workers 1], 'finished'; class(output), [numel(output) N], 'output'};
s.output_mmap.writable = true;

% Save the params
params_file = [s.work_dir 'params.mat'];
save(params_file, '-struct', 's');

% Open the memory mapped files
mi = open_mmap(s.input_mmap);
mo = open_mmap(s.output_mmap);

% Set the data
mo.Data.index = uint32(2);
mo.Data.finished(:) = 0;
mo.Data.output(:,1) = output(:);

% Start the other workers
for worker = 2:num_workers
    [a, a] = system(sprintf('matlab -automation -r "try, batch_job(''%s'', %d); catch, end; quit();" &', params_file, worker));
end

% Start the local worker
loop(func, mi, mo, s.chunk_size, 1);

% Wait for all the workers to finish
while ~all(mo.Data.finished)
    pause(0.01);
end

% Get the output
output = reshape(mo.Data.output, outsize);
end

function preallocate_file(name, nbytes)
fh = javaObject('java.io.RandomAccessFile', name, 'rw');
% Allocate the right amount of space
fh.setLength(nbytes);
% Close the file
fh.close();
end

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

function n = num_bytes(A)
n = whos('A');
n = n.bytes;
end

function nm = tmpname()
[nm, nm] = fileparts(tempname());
end

function m = open_mmap(mmap)
m = memmapfile(mmap.name, 'Format', mmap.format, 'Writable', mmap.writable, 'Repeat', 1);
end

function func = construct_function(s)
% Get the global data
if isfield(s, 'global_data')
    try
        % Try to load from a function
        global_data = feval(s.global_data);
    catch
        global_data = s.global_data;
    end
    % Get the function handle
    func = @(A) feval(s.func, reshape(A, s.insize), global_data);
else
    func = @(A) feval(s.func, reshape(A, s.insize));
end
end

function loop(func, mi, mo, n, worker)
% Initialize values
N = size(mi.Data.input, 2);
n = uint32(n);
if worker == 1 && usejava('awt')
    % Create progress function
    info.start_prop = double(mo.Data.index) / N;
    info.bar = waitbar(info.start_prop, 'Starting...', 'Name', 'Batch job processing...');
    info.timer = tic();
    progress = @(v) progressbar(info, v);
else
    progress = @(v) v;
end
% Continue until there is no more data to get
while 1
    % Get and increment the current index - assume this is atomic!
    ind = mo.Data.index;
    mo.Data.index = ind + n;
    % Check that there is stuff to be done
    ind = double(ind);
    if ind > N
        % Nothing left to do, so quit
        break;
    end
    % Compute the results
    for a = ind:min(ind+n-1, N)
        mo.Data.output(:,a) = reshape(func(mi.Data.input(:,a)), [], 1);
    end
    progress(ind/N);
end
% Flag as finished
mo.Data.finished(worker) = 1;
progress(1);
end

function progressbar(info, proportion)
% Protect against the waitbar being closed
try
    if proportion >= 1
        close(info.bar);
        drawnow;
    end
    t_elapsed = toc(info.timer);
    t_remaining = ((1 - proportion) * t_elapsed) / (proportion - info.start_prop);
    newtitle = sprintf('Elapsed: %s', timestr(t_elapsed));
    if proportion > 0.01 || t_elapsed > 30
        if t_remaining < 600
            newtitle = sprintf('%s, Remaining: %s', newtitle, timestr(t_remaining));
        else
            newtitle = sprintf('%s, ETA: %s', newtitle, datestr(datenum(clock()) + (t_remaining * 1.15741e-5), 0));
        end
    end
    waitbar(proportion, info.bar, newtitle);
catch
end
end

% Time string function
function str = timestr(t)
s = rem(t, 60);
m = rem(floor(t/60), 60);
h = floor(t/3600);

if h > 0
    str= sprintf('%dh%02dm%02.0fs', h, m, s);
elseif m > 0
    str = sprintf('%dm%02.0fs', m, s);
else
    str = sprintf('%2.1fs', s);
end
end
