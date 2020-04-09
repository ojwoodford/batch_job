function [out1, out2] = batch_job_test()
% Check batch_job_worker can be found by a worker
check_on_path('');

% Test two methods work and give the same result as a normal for loop
I = 1:500;

tic;
out3 = batch_job(@slow_func, I, '-progress');
t3 = toc;

tic;
out2 = batch_job_distrib(@slow_func, I, '-progress');
t2 = toc;

tic;
for a = I
    out1(:,:,a) = slow_func(a);
end
t1 = toc;

fprintf('For loop: %gs. Batch_job_distrib: %gs. Batch_job: %gs. Equal: %d %d.\n', t1, t2, t3, isequal(out1, out2), isequal(out1, out3));

% Test timeouts and error catching
out1 = batch_job_distrib(@random_func, 1:20, '-progress', '-timeout', -4);
out2 = batch_job(@random_func, 1:20, '-progress', '-timeout', 4);
end

function out = slow_func(in)
rng(in);
out = rand(3);
pause(0.1);
end

function out = random_func(in, sz)
assert(mod(in, 13) ~= 0, 'Unlucky for some');
seed = now() * 1000;
seed = floor((seed - floor(seed)) * (2 ^ 32));
rng(seed);
if nargin < 2
    sz = 2; %ceil(rand(1) * 3);
end
out = rand(sz);
t = rand(1) * 4.4;
pause(t);
end
