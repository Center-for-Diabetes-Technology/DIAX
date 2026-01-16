function fig = plotWeekly(obj, fig)

if nargin < 2
    if ishandle(obj.figHandle)
        fig = figure(obj.figHandle);
    else
        fig = figure(obj.figHandle);
        set(fig, 'name', 'Subject::plot', ...
            'numbertitle', 'off', ...
            'units', 'normalized', ...
            'outerposition', [0, 0, 1, 1], ...
            'defaultAxesColorOrder', [[1, 0, 0]; [0, 0, 1]]);
    end
end

if obj.isEmpty
    warning('[Subject][plot] No Data!');
    return;
end

clf(fig);
nbrWeeks = ceil(days(obj.duration)/7);
verticalGap = 0.01;
for weekNo = 1:nbrWeeks
    ax0k = subplot('Position', [0.05, 0.1+(1-weekNo/nbrWeeks)*(0.85 + verticalGap), 0.65, (0.85 - (nbrWeeks-1)*verticalGap)/nbrWeeks]);
    ax0k = obj.getWeek(weekNo).plotData(ax0k);
    ax0k.XLim = [0, 7*24*60];
    if weekNo < nbrWeeks
        ax0k.XLabel.String = '';
        ax0k.XTickLabel = {};
    end
    if weekNo == 1
        title(ax0k, sprintf('Data for participant %s: %s -> %s', obj.name, datestr(obj.startDate), datestr(obj.endDate)), 'FontSize', 16, 'Interpreter', 'none');
    else
        ax0k.Title.String = '';        
    end
    if weekNo ~= ceil(nbrWeeks/2)
        if ~isempty(obj.getWeek(weekNo).basalRate)
            yyaxis(ax0k, 'right');
            ax0k.YLabel.String = '';
            yyaxis(ax0k, 'left');
            ax0k.YLabel.String = '';
        else
            ax0k.YLabel.String = '';
        end
    else
        if weekNo == nbrWeeks/2
            ax0k.YLabel.Position(2) = 0;
        end
    end
end

ax1 = subplot('Position', [0.75, 0.2, 0.2, 0.55]);
ax1 = obj.generateSummary(ax1);

end
