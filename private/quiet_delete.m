function quiet_delete(varargin)
s = warning('off');
co = onCleanup(@() warning(s));
for fname = varargin
    if exist(fname{1}, 'file')
        delete(fname{1});
    end
end
end
