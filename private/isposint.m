% Check if an input is a positive integer
function tf = isposint(A)
tf = isscalar(A) && isnumeric(A) && round(A) == A && A > 0;
end