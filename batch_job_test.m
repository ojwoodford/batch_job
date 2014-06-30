function batch_job_test

I = 1:200;

tic;
out2 = batch_job_distrib(@slow_func, I, '-progress');
t2 = toc;

tic;
for a = I
    out1(:,:,a) = slow_func(a);
end
t1 = toc;

fprintf('For loop: %gs. Batch job: %gs. Equal: %d.\n', t1, t2, isequal(out1, out2));

function out = slow_func(in)
rng(in);
out = rand(3);
pause(0.1);