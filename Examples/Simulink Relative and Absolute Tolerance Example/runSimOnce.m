function results = runSimOnce(inputData,global_data)
simOut = sim('Example_model','RelTol', num2str(relTol), 'AbsTol', num2str(absTol));
results = simOut.yout{1}.Values;
end

