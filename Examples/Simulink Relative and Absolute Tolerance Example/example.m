%% Simulink Example
% This example loops over a simulink model changing the relative tolerance
% and absolute tolerance. Note that Simulink has optimizations such as
% "fast restart", "accelerator mode", and "rapid accelerator mode" that
% possibly could speed up simulation. However, none of these can be used in
% such a way that you are changing the relative tolerance and absolute
% tolerance from iteration to iteration. Instead, incorrect results or
% errors occur if you use any of the Simulink speed optimizations.
%% clean up
clc; clear all; close all %#ok<CLALL>

%% Constants
MODEL = 'Example_Model';
FUNC = @runSimOnce;

%% Simulation with High Accuracy
% simulate a model with high accuracy for reference
simOut = sim(MODEL, 'relTol', '1e-12', 'absTol', '1e-15');
p2Refernce = simOut.yout{1}.Values;

%% Run simulation with different relative and absolute tolerances

% setup global_data
relativeToleranceVector = logspace(-10,1,10);
absoluteToleranceVector = logspace(-10,1,11);
[global_data.relTol, global_data.absTol] = ndgrid(relativeToleranceVector,absoluteToleranceVector);
global_data.model = MODEL;

% setup input data
linearIndex = 1:numel(global_data.relTol);

results = batch_job_distrib(FUNC, linearIndex, global_data,'-progress', true,'-keep', true);
results = reshape(results, size(global_data.relTol));

%% Analysis
resultsLength = cellfun(@(x) x.Length(), results);
absoluteDifference = cellfun(@(x) p2Refernce-x.resample(p2Refernce.Time), results, 'UniformOutput', false);
relativeDifference = cellfun(@(x) x./p2Refernce*100, absoluteDifference, 'UniformOutput', false);
maxAbsoluteDifference = cellfun(@(x) max(abs(x.Data)), absoluteDifference);
maxRelativeDifference = cellfun(@(x) max(abs(x.Data)), relativeDifference);