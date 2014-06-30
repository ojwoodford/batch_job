function tf = kill_signal(s)
% Signalled if the params file is deleted
if nargout > 0
    tf = exist(s.params_file, 'file') == 0;
else
    quiet_delete(s.params_file);
end
end