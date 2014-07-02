% Convert the output to a matrix or array
function output = matrify(output)
if ~iscell(output{1}) && ~isnumeric(output{1})
    return;
end
sz = size(output{1});
if ~all(cellfun(@(c) isequal(size(c), sz), output, 'UniformOutput', true))
    return;
end
sz = numel(sz) + (sz(end) ~= 1);
output = cat(sz, output{:});
end
