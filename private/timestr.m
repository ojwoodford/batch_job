% Time string function
function str = timestr(t)
s = min(rem(t, 60), 59);
m = rem(floor(t/60), 60);
h = floor(t/3600);

if h > 0
    str= sprintf('%dh%02dm%02.0fs', h, m, s);
elseif m > 0
    str = sprintf('%dm%02.0fs', m, s);
else
    str = sprintf('%2.1fs', s);
end
end