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

