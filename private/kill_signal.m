function tf = kill_signal(s)
% Signalled if the params file is deleted
tf = exist(s.params_file, 'file') == 0;
end