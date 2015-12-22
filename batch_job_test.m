function out = batch_job_test
% Test two methods work and give the same result as a normal for loop
I = 1:500;

tic;
out2 = batch_job_distrib(@slow_func, I, '-progress');
t2 = toc;

tic;
out3 = batch_job(@slow_func, I);
t3 = toc;

tic;
for a = I
    out1(:,:,a) = slow_func(a);
end
t1 = toc;

fprintf('For loop: %gs. Batch_job_distrib: %gs. Batch_job: %gs. Equal: %d %d.\n', t1, t2, t3, isequal(out1, out2), isequal(out1, out3));

% Test timeouts and error catching
out = batch_job_distrib(@random_func, 1:50, '-progress', '-timeout', -1);
end

function out = slow_func(in)
rng(in);
out = rand(3);
pause(0.1);
end

function out = random_func(in)
assert(mod(in, 13) ~= 0, 'Unlucky for some');
seed = now;
seed = floor((seed - floor(seed)) * 2^32);
rng(seed);
out = rand(ceil(rand(1) * 3));
pause(rand(1) * 1.1);
end
