clc; clear; close all

%% Load Very Accurate Simulation
% relative tolerance was set to 1e-10
% absolute tolerance was set to auto
% Shape Preservation was enabled
load('Reference Curve.mat')
p2Refernce = yout{1}.Values;

%% Run simulation with different relative and absolute tolerances
relativeToleranceVector = logspace(-10,1,100);
absoluteToleranceVector = logspace(-10,1,101);
results = cell(length(relativeToleranceVector), length(absoluteToleranceVector));

model = 'Example_Model';
set_param(model, 'RelTol', '1e-10');
set_param(model,'AbsTol','1e-13');
set_param(model,'fastrestart','on');
set_param(model,'SimulationMode', 'Accelerator');
counter = 0;


for iRelTol = 1:length(relativeToleranceVector)
    for iAbsTol = 1:length(absoluteToleranceVector)
        relTol = relativeToleranceVector(iRelTol);
        absTol = absoluteToleranceVector(iAbsTol);
        results{iRelTol,iAbsTol} = runSimOnce(relTol,absTol);
        counter = counter + 1;
        disp(counter);
    end
end
set_param(model,'fastrestart','on');
save('Results Curves.mat','results');
% absoluteDifference = cellfun(@(x) p2Refernce-x.resample(p2Refernce.Time), results, 'UniformOutput', false);
