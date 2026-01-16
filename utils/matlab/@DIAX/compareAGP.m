function fig = compareAGP(obj1, obj2, varargin)

figHandle = mod(sum([obj1.figHandle]) + sum([obj2.figHandle]) +  1, 1e6);
if ishandle(figHandle)
    fig = figure(figHandle);
else
    fig = figure(figHandle);
    set(fig, 'name', 'Subject::plotSummary', ...
        'numbertitle', 'off', ...
        'units', 'normalized', ...
        'outerposition', [0, 0, 1, 1], ...
        'defaultAxesColorOrder', [[1, 0, 0]; [0, 0, 1]]);
end
clf(fig);

axes1 = gobjects(5,1);
axes1(4) = subplot('Position', [0.03 0.59 0.22 0.37]);
axes1(1) = subplot('Position', [0.30 0.57 0.45 0.40]);
axes1(5) = subplot('Position', [0.78 0.57 0.22 0.37]);
obj1.plotAGP(axes1);

axes2 = gobjects(5,1);
axes2(4) = subplot('Position', [0.03 0.09 0.22 0.37]);
axes2(1) = subplot('Position', [0.30 0.07 0.45 0.40]);
axes2(5) = subplot('Position', [0.78 0.07 0.22 0.37]);
obj2.plotAGP(axes2);