classdef onCleanup_ < handle
    properties(SetAccess = 'private', GetAccess = 'public', Transient)
        task_list = cell(0);
    end
    
    methods
        function this = onCleanup_(func)
            this.task_list{1} = func;
        end
        
        function delete(this)
            for a = 1:numel(this.task_list)
                try
                    this.task_list{a}();
                catch me
                    warning(getReport(me, 'extended', 'hyperlinks', 'on'));
                end
            end
        end
        
        function append(this, func)
            this.task_list{end+1} = func;
        end
        
        function prepend(this, func)
            this.task_list = [{func}; this.task_list(:)];
        end
        
        function replace(this, func, ind)
            if nargin < 3
                this.task_list = {func};
            else
                this.task_list{ind} = func;
            end
        end
    end
end