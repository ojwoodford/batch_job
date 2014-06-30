%GET_FILE_LOCK Grab a file lock for exclusive access to a file
%
%   lock = get_file_lock(fname, [force])
%
% Grab a file lock associated with a particular file. The lock is a mutex -
% only one MATLAB instance can  hold the lock at a time. The lock is
% released when the output object is cleared.
%
%IN:
%   fname - string name or path of the file to lock. The lock is given the
%           name [fname '.lock'].
%   force - indicates whether to try to grab the lock, even if the lock
%           file exists. Default: false.
%
%OUT:
%   lock - [] if the lock was not obtained, otherwise, not empty. The
%          object should be cleared, by calling clear('lock'), when the
%          lock is to be released.

function lock = get_file_lock(fname, force)
% Attempt to grab the lock
fname = [fname '.lock'];
% Check that the file exists (backup in case file locking not supported)
if exist(fname, 'file') && (nargin < 2 || ~force)
    lock = [];
    return
end
jh = javaObject('java.io.RandomAccessFile', fname, 'rw');
lock = jh.getChannel().tryLock();
if isempty(lock)
    % Failed - something else has the lock
    jh.close();
else
    % Succeeded - make sure the lock is deleted when finished with
    lock = onCleanup(@() cleanup_lock(lock, jh, fname));
end
end

function cleanup_lock(lock, jh, fname)
% Free and delete the lock file
lock.release();
jh.close();
delete(fname);
end