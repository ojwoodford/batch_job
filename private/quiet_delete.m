function quiet_delete(varargin)
for fname = varargin
    if exist(fname{1}, 'file')
        delete(fname{1});
    end
end
end
