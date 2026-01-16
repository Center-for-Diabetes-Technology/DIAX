function fig = plotAGP(obj, axes)

if nargin < 2
    figHandle = mod(sum([obj.figHandle]) +  1, 1e6);
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
    axes(1) = subplot('Position', [0.05, 0.59, 0.65, 0.35]);
    if obj.duration > days(7)
        axes(2) = subplot('Position', [0.05, 0.29, 0.65, 0.19]);
        axes(3) = subplot('Position', [0.05, 0.08, 0.65, 0.19]);
    else
        axes(2) = subplot('Position', [0.05, 0.09, 0.65, 0.38]);
    end
    axes(4) = subplot('Position', [0.73, 0.59, 0.25, 0.35]);
    axes(5) = subplot('Position', [0.78, 0.07, 0.15, 0.45]);
end

cla(axes(1));
hold(axes(1), 'on');
set(axes(1), 'FontWeight', 'bold', 'LineWidth', 2.0, 'FontSize', 14);

hypo2_color = [141, 45, 48]/255;
hypo1_color = [200, 38, 47]/255;
tir_color = [51, 162, 82]/255;
hyper1_color = [229, 168, 41]/255;
hyper2_color = [217, 123, 45]/255;

stepTime_ = 5;
duration_ = days(1);
startTime_ = 0;
dataDays = obj.getDays().getSampledData(stepTime_, 'starttime', startTime_, 'duration', duration_);

% time
t = mean([dataDays.time], 2) + startTime_;

% target
plot(axes(1), [t(1), t(end)], [180.0, 180.0], '-k');
plot(axes(1), [t(1), t(end)], [70.0, 70.0], '-k');

% cgm
cgm.mean = mean([dataDays.cgm], 2, 'omitnan');
cgm.median = median([dataDays.cgm], 2, 'omitnan');
cgm.std = std([dataDays.cgm], [], 2, 'omitnan');
cgm.iqr05 = prctile([dataDays.cgm], 05, 2);
cgm.iqr25 = prctile([dataDays.cgm], 25, 2);
cgm.iqr75 = prctile([dataDays.cgm], 75, 2);
cgm.iqr95 = prctile([dataDays.cgm], 95, 2);

% filter curves
for fn = fieldnames(cgm)'
    cgm.(fn{1}) = movmean(cgm.(fn{1}), 5);
end

idxValid = ~isnan(cgm.mean);

get_envelop_down = @(x_down, x_up, thresh)([min(thresh, x_up); flipud(min(thresh, x_down))]);
get_envelop_up = @(x_down, x_up, thresh)([max(thresh, x_down); flipud(max(thresh, x_up))]);
get_envelop = @(x_down, x_up)([min(180, max(70, x_down)); flipud(max(70, min(180, x_up)))]);

patch(axes(1), 'XData', [t(idxValid); flipud(t(idxValid))] ...
    , 'YData', get_envelop_down(cgm.iqr05(idxValid), cgm.iqr95(idxValid), 54), ...
    'EdgeColor', 'none', ...
    'FaceColor', hypo2_color, ...
    'FaceAlpha', .1)
patch(axes(1), 'XData', [t(idxValid); flipud(t(idxValid))] ...
    , 'YData', get_envelop_down(cgm.iqr05(idxValid), cgm.iqr95(idxValid), 70), ...
    'EdgeColor', 'none', ...
    'FaceColor', hypo1_color, ...
    'FaceAlpha', .1)
patch(axes(1), 'XData', [t(idxValid); flipud(t(idxValid))] ...
    , 'YData', get_envelop_up(cgm.iqr05(idxValid), cgm.iqr95(idxValid), 180), ...
    'EdgeColor', 'none', ...
    'FaceColor', hyper1_color, ...
    'FaceAlpha', .1)
patch(axes(1), 'XData', [t(idxValid); flipud(t(idxValid))] ...
    , 'YData', get_envelop_up(cgm.iqr05(idxValid), cgm.iqr95(idxValid), 250), ...
    'EdgeColor', 'none', ...
    'FaceColor', hyper2_color, ...
    'FaceAlpha', .1)

patch(axes(1), 'XData', [t(idxValid); flipud(t(idxValid))] ...
    , 'YData', get_envelop_down(cgm.iqr25(idxValid), cgm.iqr75(idxValid), 54), ...
    'EdgeColor', 'none', ...
    'FaceColor', hypo2_color, ...
    'FaceAlpha', .3)
patch(axes(1), 'XData', [t(idxValid); flipud(t(idxValid))] ...
    , 'YData', get_envelop_down(cgm.iqr25(idxValid), cgm.iqr75(idxValid), 70), ...
    'EdgeColor', 'none', ...
    'FaceColor', hypo1_color, ...
    'FaceAlpha', .3)
patch(axes(1), 'XData', [t(idxValid); flipud(t(idxValid))] ...
    , 'YData', get_envelop_up(cgm.iqr25(idxValid), cgm.iqr75(idxValid), 180.5), ...
    'EdgeColor', 'none', ...
    'FaceColor', hyper1_color, ...
    'FaceAlpha', .3)
patch(axes(1), 'XData', [t(idxValid); flipud(t(idxValid))] ...
    , 'YData', get_envelop_up(cgm.iqr25(idxValid), cgm.iqr75(idxValid), 250), ...
    'EdgeColor', 'none', ...
    'FaceColor', hyper2_color, ...
    'FaceAlpha', .3)

patch(axes(1), 'XData', [t(idxValid); flipud(t(idxValid))] ...
    , 'YData', get_envelop(cgm.iqr05(idxValid), cgm.iqr95(idxValid)), ...
    'EdgeColor', 'none', ...
    'FaceColor', tir_color, ...
    'FaceAlpha', .1)
patch(axes(1), 'XData', [t(idxValid); flipud(t(idxValid))] ...
    , 'YData', get_envelop(cgm.iqr25(idxValid), cgm.iqr75(idxValid)), ...
    'EdgeColor', 'none', ...
    'FaceColor', tir_color, ...
    'FaceAlpha', .3)

plot(axes(1), t(idxValid), cgm.mean(idxValid), ...
    'Color', 'k', ...
    'LineStyle', '-', ...
    'Marker', '.', ...
    'MarkerSize', 20);

ylim(axes(1), [0, 400])
yticks(axes(1), 0:40:400);
axes(1).YLabel.String = 'Sensor Glucose (mg/dl)';

xlim(axes(1), [t(1) - 30, t(end) + 30]);
sTick = 2*60;
st_ = 0.0;
xticks(axes(1), (sTick*floor((t(1)+st_) / (sTick)):sTick:sTick*ceil((t(end)+st_) / (sTick)))-st_);
xticklabels(axes(1), [num2str((sTick/60*floor((t(1)+st_) / (sTick)):sTick/60:sTick/60*ceil((t(end)+st_) / (sTick)))'), repmat(':00', length(sTick / 60 * floor((t(1)+st_) / (sTick)):sTick / 60:sTick / 60 * ceil((t(end)+st_) / (sTick))), 1)]);
axes(1).XLabel.String = 'Time (HH:MM)';
axes(1).XLabel.FontSize = 14;
axes(1).XGrid = 'on';

%%
eCarbCategory = {'L', 'M', 'H'};
blue_ = [65,105,225]/255;
stepTime_ = 5;
duration_ = days(7);
startTime_ = 0;
dataWeeks = obj.getWeeks().getSampledData(stepTime_, 'fields', {'cgm', 'basalRate', 'bolus', 'carbsCategory'}, 'starttime', startTime_, 'duration', duration_, 'fill', false);

for kk = 1:length(dataWeeks)
    if ~isgraphics(axes(kk + 1))
        continue;
    end
    cla(axes(kk + 1));
    hold(axes(kk + 1), 'on');
    set(axes(kk + 1), 'FontWeight', 'bold', 'LineWidth', 2.0, 'FontSize', 14);

    t = dataWeeks(kk).time + startTime_;
    plot(axes(kk + 1), t(dataWeeks(kk).cgm < 70), dataWeeks(kk).cgm(dataWeeks(kk).cgm < 70), ...
        'Color', hypo1_color, ...
        'LineStyle', 'none', ...
        'Marker', '.', ...
        'MarkerSize', 12);
    plot(axes(kk + 1), t(dataWeeks(kk).cgm > 180.5), dataWeeks(kk).cgm(dataWeeks(kk).cgm > 180.5), ...
        'Color', hyper1_color, ...
        'LineStyle', 'none', ...
        'Marker', '.', ...
        'MarkerSize', 12);
    plot(axes(kk + 1), t(dataWeeks(kk).cgm >= 70 & dataWeeks(kk).cgm < 180.5), dataWeeks(kk).cgm(dataWeeks(kk).cgm >= 70 & dataWeeks(kk).cgm < 180.5), ...
        'Color', tir_color, ...
        'LineStyle', 'none', ...
        'Marker', '.', ...
        'MarkerSize', 12);
    patch(axes(kk + 1), ...
        'XData', [t; flipud(t)], ...
        'YData', [70*ones(size(t)); flipud(180*ones(size(t)))], ...
        'EdgeColor', 'none', ...
        'FaceColor', 'k', ...
        'FaceAlpha', .05)
    yline(axes(kk + 1), 70, 'LineWidth', 2.0);
    yline(axes(kk + 1), 180, 'LineWidth', 2.0);

    for jj = find(dataWeeks(kk).bolus > 0)'
        plot(axes(kk + 1), t(jj), 300, 'v', 'MarkerFaceColor', blue_, 'MarkerEdgeColor', blue_);
        xline(axes(kk + 1), t(jj), '--', 'Color', blue_);
    end
    if isfield(dataWeeks(kk), 'carbsCategory')
        for jj = find(dataWeeks(kk).carbsCategory > 0)'
            text(axes(kk + 1), t(jj)-30, 350, eCarbCategory{dataWeeks(kk).carbsCategory(jj)}, 'Color', 'r', 'FontWeight', 'bold');
            % xline(axes(kk + 1), t(jj), '-', 'Color', 'r');
        end
    end

    if isfield(dataWeeks(kk), 'basalRate') && nansum(dataWeeks(kk).basalRate) > 0
        yyaxis(axes(kk + 1), "right")
        bar(axes(kk + 1), t, dataWeeks(kk).basalRate,'FaceColor', blue_, 'EdgeColor', 'none', 'FaceAlpha', 0.3);
        axes(kk + 1).YAxis(2).Color = [0 0 0];
        axes(kk + 1).YAxis(2).Limits = [0 10];
        axes(kk + 1).YLabel.String = 'Basal Rate (U/h)';
        yyaxis(axes(kk + 1), "left")
    end

    xlim(axes(kk + 1), [t(1) - 30, t(end) + 30]);

    ylim(axes(kk + 1), [0, 400])
    yticks(axes(kk + 1), [70, 180]);

    axes(kk + 1).YLabel.String = 'mg/dl';
    axes(kk + 1).XGrid = 'on';
    sTick = 12*60;
    st_ = 0.0;
    xticks(axes(kk + 1), (sTick*floor((t(1)+st_) / (sTick)):sTick:sTick*ceil((t(end)+st_) / (sTick)))-st_);
    if kk == length(dataWeeks)
        xticklabels(axes(kk + 1), ...
            [num2str(mod((sTick/60*floor((t(1)+st_) / (sTick)):sTick/60:sTick/60*ceil((t(end)+st_) / (sTick))), 24)'),...
            repmat(':00', length(sTick / 60 * floor((t(1)+st_) / (sTick)):sTick / 60:sTick / 60 * ceil((t(end)+st_) / (sTick))), 1)]);
    else
        xticklabels(axes(kk + 1),'');
    end

    for jj = 1:7
        xline(axes(kk + 1), 1440*jj, 'k', 'LineWidth', 2.0)
        if kk == 1
            aa = dataWeeks(kk).timestamp(dataWeeks(kk).time == 1440*(jj - 1));
            [~, dayName] = weekday(aa, 'long');
            text(axes(kk + 1), 1440*(jj - 0.5), 470, sprintf("%s\n%s", dayName, datestr(aa)), "FontSize", 12, 'FontWeight','bold', 'HorizontalAlignment','center');
        else
            aa = dataWeeks(kk).timestamp(dataWeeks(kk).time == 1440*(jj - 1));
            text(axes(kk + 1), 1440*(jj - 0.5), 430, datestr(aa), "FontSize", 12, 'FontWeight','bold', 'HorizontalAlignment','center');
        end
    end
end

%%
ax = axes(4);
hold(ax, 'on');
ax.XLim = [0, 1];
ax.YLim = [0, 1];
ax.XAxis.Visible = 'off';
ax.YAxis.Visible = 'off';
ax.Color = 'none';

rectangle(ax, 'Position', [0.0, 0.0, 1.0, 1.0], 'EdgeColor', [0.5, 0.5, 0.5], 'LineWidth', 1.5, 'FaceColor', [0.97, 0.97, 0.97]);

linesNbr = 10;
lineWidth = 0.02;
spacerNbr = 3;
marginY = 0.03;
marginX = 0.03;
lineSpacing = (1 - 2 * marginY - (linesNbr - 1) * lineWidth) / (linesNbr + spacerNbr);
linePos = @(l, s)(1 - l * lineWidth - (l + s - 1) * lineSpacing - marginY);
posX = 0.45;

line = 0;
spacer = 1;

line = line + 1;
name_ = obj.name;
name_ = strsplit(name_, '_');
if numel(name_) > 1
    name_(2:end) = [];
end
name_ = strjoin(name_, ' ');
text(ax, marginX, linePos(line, spacer), sprintf('Participant %s', name_), 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold');
plot(ax, [marginX, marginX + 0.37], [linePos(line, spacer), linePos(line, spacer)]-0.04, 'color', [0.5, 0.5, 0.5], 'LineWidth', 1.5);

line = line + 1;
text(ax, marginX, linePos(line, spacer), sprintf('%s — %s', datestr(obj.startDate, 'dd-mmm-yyyy'), datestr(obj.endDate, 'dd-mmm-yyyy')), 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold');
plot(ax, [marginX, marginX + 0.77], [linePos(line, spacer), linePos(line, spacer)]-0.04, 'color', [0.5, 0.5, 0.5], 'LineWidth', 1.5);

% line = line + 1;
% text(ax, marginX, linePos(line, spacer), sprintf('Time CGM Active: %4.1f%%', 97.8), 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold');
% plot(ax, [marginX, marginX + 0.60], [linePos(line, spacer), linePos(line, spacer)]-0.04, 'color', [0.5, 0.5, 0.5], 'LineWidth', 1.5);

spacer = spacer + 1;

line = line + 1;
text(ax, marginX, linePos(line, spacer), 'Glucose Metrics', 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold');
plot(ax, [marginX, marginX + 0.42], [linePos(line, spacer), linePos(line, spacer)]-0.04, 'color', [0.5, 0.5, 0.5], 'LineWidth', 1.5);

line = line + 1;
text(ax, marginX, linePos(line, spacer), 'Average Glucose: ', 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold');
text(ax, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.0f mg/dL', obj.getGMean()), 'Color', 'k', 'FontSize', 14, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax, marginX, linePos(line, spacer), 'GMI: ', 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold');
text(ax, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.1f%%', obj.getGMI()), 'Color', 'k', 'FontSize', 14, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax, marginX, linePos(line, spacer), 'Glucose Variability: ', 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold');
text(ax, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.1f%%', obj.getGlucoseCV()), 'Color', 'k', 'FontSize', 14, 'HorizontalAlignment', 'center');

spacer = spacer + 1;

line = line + 1;
text(ax, marginX, linePos(line, spacer), 'Insulin Metrics', 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold');
plot(ax, [marginX, marginX + 0.42], [linePos(line, spacer), linePos(line, spacer)]-0.04, 'color', [0.5, 0.5, 0.5], 'LineWidth', 1.5);

line = line + 1;
text(ax, marginX, linePos(line, spacer), 'Total Insulin', 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold');
text(ax, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.1f U', obj.getTotalInsulin()/days(obj.duration)), 'Color', 'k', 'FontSize', 14, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax, marginX, linePos(line, spacer), 'Basal Insulin', 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold');
text(ax, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.1f U', obj.getTotalBasal()/days(obj.duration)), 'Color', 'k', 'FontSize', 14, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax, marginX, linePos(line, spacer), 'Bolus Insulin', 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold');
text(ax, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.1f U', obj.getTotalBolus()/days(obj.duration)), 'Color', 'k', 'FontSize', 14, 'HorizontalAlignment', 'center');

%%
ax = axes(5);
hold(ax, 'on');
ax.XLim = [0, 1];
ax.YLim = [0, 1];
ax.XAxis.Visible = 'off';
ax.YAxis.Visible = 'off';
ax.Color = 'none';

outcomes = [ ...
    obj.getTimeIn(-inf, 54); ...
    obj.getTimeIn(54, 70); ...
    obj.getTimeIn(70, 180.5); ...
    obj.getTimeIn(180.5, 250); ...
    obj.getTimeIn(250.5, inf); ...
    ];
outcomes = round(outcomes, 1);

b = bar(ax, [0.1], outcomes/100, 'stacked');
colors = { ...
    hypo2_color; ...
    hypo1_color; ...
    tir_color; ...
    hyper1_color; ...
    hyper2_color; ...
    };

for k = 1:5
    b(k).FaceColor = colors{k};
    b(k).EdgeColor = [0.95, 0.95, 0.95];
    b(k).LineWidth = 1.0;
    b(k).BarWidth = 0.2;
    b(k).BaseLine.Visible = 'off';
end

positions_ = cumsum(outcomes) / 100;
x3 = mean(positions_(2:3));
x4 = max(x3+0.06, mean(positions_(3:4)));
x5 = max(x4+0.06, 1.02);
x2 = min(x3-0.06, mean(positions_(1:2)));
x1 = min(x2-0.06, -0.04);
text(ax, 0.2, x5, sprintf('  >250 mg/dL ——— %3.1f %%', outcomes(5)), 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'top');
text(ax, 0.2, x4, sprintf('  180–250 mg/dL —— %3.1f %%', outcomes(4)), 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
text(ax, 0.2, x3, sprintf('  70–180.0 mg/dL —— %3.1f %%', outcomes(3)), 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
text(ax, 0.2, x2, sprintf('  54–70 mg/dL ———— %3.1f %%', outcomes(2)), 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
text(ax, 0.2, x1, sprintf('  <54 mg/dL ————— %3.1f %%', outcomes(1)), 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');


end
