%% get_file_lock
% Grab a file lock for exclusive access to a file
%
%% Syntax
%   lock = get_file_lock(fname)
%   lock = get_file_lock(fname, force)
%
%% Input Arguments
% * *fname* - string name or path of the file to lock. The lock is given the
%           name [fname '.lock'].
% * *force* - indicates whether to try to grab the lock, even if the lock
%           file exists. 
%
%           Default: false
%
%% Output Arguments:
% * *lock* - epmty if the lock was not obtained, otherwise, not empty. The
%          object should be cleared, by calling clear('lock'), when the
%          lock is to be released.

%% Description
% Grab a file lock associated with a particular file. The lock is a mutex -
% only one MATLAB instance can hold the lock at a time. The lock is
% released when the output object is cleared.
%