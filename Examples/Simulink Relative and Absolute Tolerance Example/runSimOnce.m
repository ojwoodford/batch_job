function result = runSimOnce(linearIndex, global_data)
simOut = sim(global_data.model,'RelTol', num2str(global_data.relTol(linearIndex)), 'AbsTol', num2str(global_data.absTol(linearIndex)));
result = simOut.yout{1}.Values;
end

