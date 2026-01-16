function [fig, ax0, ax1] = plot(obj, varargin)
    % deprecated check for fig object being first argument
    if nargin > 1 && ~(ischar(varargin{1}) || isstring(varargin{1}))
        fprintf('Warning: The use of a figure handle as the first argument is deprecated. Use the ''fig'' or ''figure'' argument instead.\n');
        % put the figure handle in the 'fig' argument
        varargin = [{'fig', varargin{1}}, varargin(2:end)];
    end 

    figProvided = false;
    for nVar = 1:2:length(varargin)
        switch lower(varargin{nVar})
            case {'fig', 'figure'}
                fig = varargin{nVar+1};
                figProvided = true;
        end
    end
    
if numel(obj) > 1
    [fig, ax0, ax1] = obj.plotSummary(varargin{:});
    return;
end

    % Check if 'fig' or 'figure' is not in varargin
if ~figProvided
    if ishandle(obj.figHandle)
        fig = figure(obj.figHandle);
    else
        fig = figure(obj.figHandle);
        set(fig, 'name', 'DIAX::plot', ...
            'numbertitle', 'off', ...
            'units', 'normalized', ...
            'outerposition', [0, 0, 1, 1], ...
            'defaultAxesColorOrder', [[1, 0, 0]; [0, 0, 1]]);
    end
end

clf(fig);
if obj.isEmpty
    warning('[DIAX][plot] No Data!');
    return;
end

ax1 = subplot('Position', [0.79, 0.10, 0.19, 0.85]);
% add 'ax' to varargin
if iscell(varargin)
    varargin = [varargin, {'ax', ax1}];
else
    varargin = [{'ax', ax1}];
end
varargin = [{'names', {obj.name}}, varargin];  % add default name, this will get overwritten if 'names' is provided later in varargin

ax1 = DIAX.compareMetrics({obj}, varargin{:});

ax0 = subplot('Position', [0.035, 0.1, 0.74, 0.85]);
ax0 = obj.plotData(ax0);

end
