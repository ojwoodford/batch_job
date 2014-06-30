function batch_job_test

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

function out = slow_func(in)
rng(in);
out = rand(3);
pause(0.1);