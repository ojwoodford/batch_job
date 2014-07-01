Batch Job
=========

A MATLAB toolbox to parallelize simple for loops across multiple MATLAB instances, across multpile computing nodes.

### Overview

This toolbox can parallelize for loops which are of a form simlar to

```for a = 1:size(input, 2) 
       output(:,a) = func(input(:,a), global_data); 
   end```
