function fig = plotCompare(subjGrp, varargin)

% define helpfull functions
    function xOut = xDataTransform(xIn)
        xOut = kron(xIn(2:end), [1; 1]);
        xOut(2:end+1) = xOut;
        xOut(1) = xIn(1);
    end

    function yOut = yDataTransform(yIn)
        yOut = kron(yIn(1:end - 1, :), [1; 1]);
        yOut(end+1, :) = yIn(end, :);
    end

if ~iscell(subjGrp)
    subjGrp = {subjGrp};
end

colors = {...
    [0.4660, 0.6740, 0.1880], ...
    [0.8500, 0.3250, 0.0980], ...
    [0.9290, 0.6940, 0.1250], ...
    [0.4940, 0.1840, 0.5560], ...
    [0, 0.4470, 0.7410], ...
    [0.3010, 0.7450, 0.9330], ...
    [0.6350, 0.0780, 0.1840]};
names = cellfun(@(c)(strcat('subj', num2str(c))), num2cell(1:length(subjGrp)), 'UniformOutput', false);
shortnames = {};
titleString = 'default';
separate_fig_ = false;
error_bars_type_ = 'patch';
detailed_outcomes = true;
show_insulin = false;
graph_percent = 0.55;
metrics = { 'tar1', 'tar2', 'tir', 'ttir', 'tbr1', 'tbr2', ...
            'ntar', 'ntir', 'ntbr', ...
            'dtar', 'dtir', 'dtbr', ...
            'avgg', 'sdg', 'cvg', ... 
            'gmi', 'lbgi', 'hbgi', 'bgi', ... 
            'tdi', 'tdba', 'tdbo', 'ntdbo',... 
            'carbs', 'carbscount', 'carbsann', 'treat'};
for nVar = 1:2:length(varargin)
    switch lower(varargin{nVar})
        case {'name', 'names', 'legend', 'arms'}
            names = strrep(varargin{nVar+1}, '_', ' ');
        case {'shortname', 'shortnames', 'shortlegend'}
            shortnames = varargin{nVar+1};
        case {'colors', 'color'}
            colors = varargin{nVar+1};
        case 'title'
            titleString = varargin{nVar+1};
        case {'sep', 'separate'}
            separate_fig_ = varargin{nVar+1};
        case {'errorstype', 'errortype', 'errorbars', 'errorbar', 'type'}
            error_bars_type_ = varargin{nVar+1};
        case {'details', 'debug', 'detailedoutcomes', 'tableoutcomes'}
            detailed_outcomes = varargin{nVar+1};
        case {'thermometer', 'thermo'}
            detailed_outcomes = ~varargin{nVar+1};
        case {'showinsulin', 'insulin'}
            show_insulin = varargin{nVar+1};
        case 'graphpercent'
            graph_percent = varargin{nVar+1};
        case {'metric', 'metrics'}
            metrics = varargin{nVar+1};
    end
end
if isempty(shortnames)
    shortnames = names;
    for gr = 1:length(shortnames)
        if length(shortnames{gr}) > 19
            shortnames{gr} = shortnames{gr}(1:19);
        end
    end
end

subjGrpAll = [subjGrp{:}];
figHandle1 = mod(sum([subjGrpAll.figHandle], 'omitnan') + sum(double([shortnames{:}])) + 3, 9973);
if ishandle(figHandle1)
    fig1 = figure(figHandle1);
else
    fig1 = figure(figHandle1);
    set(fig1, 'name', 'Subject::plotCompare', ...
        'numbertitle', 'off', ...
        'units', 'normalized', ...
        'outerposition', [0, 0, 1, 1], ...
        'defaultAxesColorOrder', [[1, 0, 0]; [0, 0, 1]]);
end

clf(fig1);
if ~detailed_outcomes
    ax0 = subplot('Position', [0.05, 0.13, graph_percent*0.99-0.05, 0.82]);
else
    if separate_fig_
        ax0 = subplot('Position', [0.05, 0.13, 0.90, 0.82]);
    else
        ax0 = subplot('Position', [0.05, 0.13, graph_percent*0.99-0.05, 0.82]);
    end
end
ax0.Tag = 'plot';

cla(ax0);
hold(ax0, 'on');
set(ax0, 'FontWeight', 'bold', 'LineWidth', 2.0, 'FontSize', 14);

popSize = [];
for gr = numel(subjGrp):-1:1
    obj = subjGrp{gr}.copy();
    popSize(gr) = numel(obj);

    stepTime_ = 5;
    data = obj.getSampledData(stepTime_, 'fields', {});
    duration_ = mode([data.duration]);
    duration_ = days(round(days(duration_))); % duration is multiple of days
    startTime_ = mode([data.startTime]);
    data = obj.getSampledData(stepTime_, 'fields', {'cgm', 'basalRate'}, 'starttime', startTime_, 'duration', duration_);

    % time
    t = mean([data.time], 2) + startTime_;

    % target
    plot(ax0, [t(1), t(end)], [180.0, 180.0], '-k');
    plot(ax0, [t(1), t(end)], [70.0, 70.0], '-k');

    % cgm
    cgm.mean = mean([data.cgm], 2, 'omitnan');
    cgm.median = median([data.cgm], 2, 'omitnan');
    cgm.std = std([data.cgm], [], 2, 'omitnan');
    cgm.iqr05 = prctile([data.cgm], 05, 2);
    cgm.iqr25 = prctile([data.cgm], 25, 2);
    cgm.iqr75 = prctile([data.cgm], 75, 2);
    cgm.iqr95 = prctile([data.cgm], 95, 2);

    % remove all nan
    idx2Remove = isnan(cgm.mean);
    cgm.mean(idx2Remove) = [];
    cgm.median(idx2Remove) = [];
    cgm.std(idx2Remove) = [];
    cgm.iqr05(idx2Remove) = [];
    cgm.iqr25(idx2Remove) = [];
    cgm.iqr75(idx2Remove) = [];
    cgm.iqr95(idx2Remove) = [];
    t(idx2Remove) = [];


    if strcmp(error_bars_type_, 'iqr')
        PLOTNAME(gr) = plot(ax0, t, cgm.iqr25, ...
            'Color', colors{gr}, ...
            'LineWidth', 0.5, ...
            'LineStyle', '-', ...
            'Marker', 'none', ...
            'MarkerSize', 8);
        PLOTNAME(gr) = plot(ax0, t, cgm.iqr75, ...
            'Color', colors{gr}, ...
            'LineWidth', 0.5, ...
            'LineStyle', '-', ...
            'Marker', 'none', ...
            'MarkerSize', 8);
        patch(ax0, 'XData', [t; flipud(t)] ...
            , 'YData', [cgm.iqr25; flipud(cgm.iqr75)], ...
            'EdgeColor', 'none', ...
            'FaceColor', colors{gr}, ...
            'FaceAlpha', .1)
    elseif strcmp(error_bars_type_, 'patch')
        PLOTNAME(gr) = plot(ax0, t, cgm.iqr05, ...
            'Color', colors{gr}, ...
            'LineWidth', 0.5, ...
            'LineStyle', '-', ...
            'Marker', 'none', ...
            'MarkerSize', 8);
        PLOTNAME(gr) = plot(ax0, t, cgm.iqr95, ...
            'Color', colors{gr}, ...
            'LineWidth', 0.5, ...
            'LineStyle', '-', ...
            'Marker', 'none', ...
            'MarkerSize', 8);
        patch(ax0, 'XData', [t; flipud(t)] ...
            , 'YData', [cgm.iqr05; flipud(cgm.iqr95)], ...
            'EdgeColor', colors{gr}, ...
            'FaceColor', colors{gr}, ...
            'FaceAlpha', .1)
    end
    PLOTNAME(gr) = plot(ax0, t, cgm.median, ...
        'Color', colors{gr}, ...
        'LineWidth', 2.0, ...
        'LineStyle', '-', ...
        'Marker', 'none', ...
        'MarkerSize', 8);

    ylim(ax0, [40, 400]);
    yticks(ax0, 0:40:400);
    xlim(ax0, [t(1) - 30, t(end) + 30]);

    if t(end) - t(1) <= 2 * 60
        sTick = 0.5 * 60;
    elseif t(end) - t(1) <= 8 * 60
        sTick = 1 * 60;
    elseif t(end) - t(1) <= 24 * 60
        sTick = 2 * 60;
    elseif t(end) - t(1) <= 48 * 60
        sTick = 4 * 60;
    elseif t(end) - t(1) <= 5 * 24* 60
        sTick = 12 * 60;
    elseif t(end) - t(1) <= 8 * 7 * 24* 60
        sTick = 24 * 60;
    else
        sTick = 7 * 24 * 60;
    end
    st_ = 0.0;
    xticks(ax0, t(1):sTick:t(end));
    if sTick < 1440
        xticklabels(ax0, [num2str(mod((sTick/60*floor((t(1)+st_) / (sTick)):sTick/60:sTick/60*ceil((t(end)+st_) / (sTick)))', 24)), repmat(':00', length(sTick / 60 * floor((t(1)+st_) / (sTick)):sTick / 60:sTick / 60 * ceil((t(end)+st_) / (sTick))), 1)]);
        ax0.XLabel.String = 'Time (HH:MM)';
    else
        xticklabels(ax0, ((sTick*floor((t(1)+st_) / (sTick)):sTick:sTick*ceil((t(end)+st_) / (sTick)))-st_)/1440);
        ax0.XLabel.String = 'Time (days)';
    end
    ax0.YLabel.String = 'Sensor Glucose (mg/dl)';

    if show_insulin && ~isempty(data(1).basalRate) && sum(data(1).basalRate) > 0
        % basal rate
        yyaxis(ax0, 'right');
        basalRate.mean = mean([data.basalRate], 2, 'omitnan');
        basalRate.median = median([data.basalRate], 2, 'omitnan');
        basalRate.std = std([data.basalRate], [], 2, 'omitnan');
        basalRate.iqr05 = prctile([data.basalRate], 05, 2);
        basalRate.iqr25 = prctile([data.basalRate], 25, 2);
        basalRate.iqr75 = prctile([data.basalRate], 75, 2);
        basalRate.iqr95 = prctile([data.basalRate], 95, 2);

        tbarate = t;
        % patch(ax0, 'XData', [xDataTransform(tbarate); flipud(xDataTransform(tbarate))] ...
        %     , 'YData', [yDataTransform(basalRate.iqr05); flipud(yDataTransform(basalRate.iqr95))], ...
        %     'EdgeColor', 'none', ...
        %     'FaceColor', blue, ...
        %     'FaceAlpha', .1);
        patch(ax0, 'XData', [xDataTransform(tbarate); flipud(xDataTransform(tbarate))] ...
            , 'YData', [yDataTransform(basalRate.iqr25); flipud(yDataTransform(basalRate.iqr75))], ...
            'EdgeColor', colors{gr}, ...
            'FaceColor', colors{gr}, ...
            'FaceAlpha', .2);
        plot(ax0, xDataTransform(tbarate), yDataTransform(basalRate.mean), ...
            'Color', colors{gr}, ...
            'LineWidth', 2.0, ...
            'LineStyle', '-', ...
            'LineWidth', 2.0);

        ax0.YAxis(2).Color = [0, 0, 0];
        ax0.YLabel.String = 'Insulin Rate (U/h)';
        ax0.YLim = [0, 20];
        ax0.YTick = (0:1:20);

        yyaxis(ax0, 'left');
        ax0.YAxis(2).Color = [0, 0, 0];
    end
end

if strcmp(titleString, 'default')
    for gr = numel(subjGrp):-1:1
        text_{gr} = sprintf('%s (n=%d)', names{gr}, popSize(gr));
    end
    title(ax0, ['Comparison ', sprintf(' %s ', text_{:})], 'FontSize', 16, 'Interpreter', 'none');
else
    title(ax0, titleString, 'FontSize', 16, 'Interpreter', 'none');
end

legend(PLOTNAME, names);

%%
if separate_fig_
    figHandle2 = mod(sum([subjGrpAll.figHandle], 'omitnan') + sum(double([shortnames{:}])) + 13, 9973);
    if ishandle(figHandle2)
        fig2 = figure(figHandle2);
    else
        fig2 = figure(figHandle2);
        set(fig2, 'name', 'Subject::plotCompareSummary', ...
            'numbertitle', 'off', ...
            'units', 'normalized', ...
            'outerposition', [0, 0, 0.5, 1], ...
            'defaultAxesColorOrder', [[1, 0, 0]; [0, 0, 1]]);
    end
    clf(fig2);
end

    function writeAverageInfo(infoArray, col)
        text(ax1, marginX + posX + (col-1)*offset, linePos(line, spacer), sprintf('%4.2f (%4.2f)', mean(infoArray, "omitnan"), std(infoArray, [], 'omitnan')), 'Color', 'k', 'FontSize', 12);
    end

    function writeDifference(info1, info2)
        if length(info1) ~= length(info2)
            [~, pValue] = ttest2(info1, info2);
            text(ax1, marginX + posX + 2*offset, linePos(line, spacer), sprintf('%4.2f (P=%4.2f)', mean(info2)-mean(info1), pValue), 'Color', 'k', 'FontSize', 12);
        else
            [~, pValue] = ttest(info1, info2);
            text(ax1, marginX + posX + 2*offset, linePos(line, spacer), sprintf('%4.2f (P=%4.2f)', mean(info2-info1), pValue), 'Color', 'k', 'FontSize', 12);
        end
    end

if detailed_outcomes
    if separate_fig_
        ax1 = subplot('Position', [0.05, 0.05, 0.90, 0.90]);
    else
        ax1 = subplot('Position', [graph_percent*1.0, 0.15, (1-graph_percent)*0.99, 0.70]);
    end
    
    ax1 = Subject.compareMetrics(subjGrp, 'metrics', metrics, 'ax', ax1, 'names', shortnames, 'colors', colors);
else
    if numel(subjGrp) == 2
        ax3 = subplot('Position', [graph_percent*1.01, 0.43, (1-graph_percent)*0.99, 0.48]);
        ax3.Tag = 'summary-glucose';

        hold(ax3, 'on');
        ax3.XLim = [0, 1];
        ax3.YLim = [0, 1];
        ax3.XAxis.Visible = 'off';
        ax3.YAxis.Visible = 'off';
        ax3.Color = 'none';

        hypo2_color = [141, 45, 48]/255;
        hypo1_color = [200, 38, 47]/255;
        tir_color = [51, 162, 82]/255;
        hyper1_color = [229, 168, 41]/255;
        hyper2_color = [217, 123, 45]/255;
        colors = { ...
            hypo2_color; ...
            hypo1_color; ...
            tir_color; ...
            hyper1_color; ...
            hyper2_color; ...
            };

        cgm_out_1 = [ ...
            mean(subjGrp{1}.getTimeIn(-inf, 54)); ...
            mean(subjGrp{1}.getTimeIn(54, 70)); ...
            mean(subjGrp{1}.getTimeIn(70, 180.5)); ...
            mean(subjGrp{1}.getTimeIn(180.5, 250)); ...
            mean(subjGrp{1}.getTimeIn(250, inf)); ...
            ];
        cgm_out_1 = round(cgm_out_1, 1);

        cgm_out_2 = [ ...
            mean(subjGrp{2}.getTimeIn(-inf, 54)); ...
            mean(subjGrp{2}.getTimeIn(54, 70)); ...
            mean(subjGrp{2}.getTimeIn(70, 180.5)); ...
            mean(subjGrp{2}.getTimeIn(180.5, 250)); ...
            mean(subjGrp{2}.getTimeIn(250.5, inf)); ...
            ];
        cgm_out_2 = round(cgm_out_2, 1);

        b = bar(ax3, [0.1 0.92], [cgm_out_1 cgm_out_2]/100, 'stacked');

        for k = 1:length(cgm_out_1)
            b(k).FaceColor = colors{k};
            b(k).EdgeColor = [0.95, 0.95, 0.95];
            b(k).LineWidth = 1.0;
            b(k).BarWidth = 0.1;
            b(k).BaseLine.Visible = 'off';
        end

        positions_ = cumsum(mean(cgm_out_1, 2)) / 100;
        x3 = mean(positions_(2:3));
        x4 = max(x3+0.06, mean(positions_(3:4)));
        x5 = max(x4+0.06, 1.02);
        x2 = min(x3-0.04, mean(positions_(1:2)));
        x1 = min(x2-0.12, -0.05);
        text(ax3, 0.15, x5, sprintf('  %3.1f %% ——— >250 mg/dL ——— %3.1f %%  ', cgm_out_1(5), cgm_out_2(5)), 'Color', hyper2_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'top');
        text(ax3, 0.15, x4, sprintf(' %3.1f %% —— 180–250 mg/dL —— %3.1f %%  ', cgm_out_1(4), cgm_out_2(4)), 'Color', hyper1_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
        text(ax3, 0.15, x3, sprintf(' %3.1f %% —— 70–180.0 mg/dL —— %3.1f %%  ', cgm_out_1(3), cgm_out_2(3)), 'Color', tir_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
        text(ax3, 0.15, x2, sprintf('  %3.1f %% ——— 54–70 mg/dL ——— %3.1f %%  ', cgm_out_1(2), cgm_out_2(2)), 'Color', hypo1_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
        text(ax3, 0.15, x1, sprintf('%3.1f %% ———— <54 mg/dL ———— %3.1f %%  ', cgm_out_1(1), cgm_out_2(1)), 'Color', hypo2_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');

        % insulin bars
        ax2 = subplot('Position', [0.72, 0.07, 0.26, 0.3]);
        ax2.Tag = 'summary-insulin';

        hold(ax2, 'on');
        ax2.XLim = [0, 1];
        ax2.YLim = [0, 1];
        ax2.XAxis.Visible = 'off';
        ax2.YAxis.Visible = 'off';
        ax2.Color = 'none';

        basal_color = [51,102,255]/255;
        bolus_color = [119,170,255]/255;
        colors = { ...
            basal_color; ...
            bolus_color; ...
            };

        ins_out_1 = [ ...
            mean(subjGrp{1}.getTotalBasal())/days(duration_); ...
            mean(subjGrp{1}.getTotalBolus())/days(duration_); ...
            ];
        ins_out_1 = round(ins_out_1, 1);

        ins_out_2 = [ ...
            mean(subjGrp{2}.getTotalBasal())/days(duration_); ...
            mean(subjGrp{2}.getTotalBolus())/days(duration_); ...
            ];
        ins_out_2 = round(ins_out_2, 1);

        b = bar(ax2, [0.1 0.92], [ins_out_1 ins_out_2]/(10*round(max(sum([ins_out_1 ins_out_2]))*1.1/10)), 'stacked');

        for k = 1:length(ins_out_2)
            b(k).FaceColor = colors{k};
            b(k).EdgeColor = [0.95, 0.95, 0.95];
            b(k).LineWidth = 1.0;
            b(k).BarWidth = 0.1;
            b(k).BaseLine.Visible = 'off';
        end

        positions_ = cumsum(mean(ins_out_1, 2))/(10*round(max(sum([ins_out_1 ins_out_2]))*1.1/10));
        x2 = mean(positions_(1:2));
        x1 = positions_(1)*0.5;
        text(ax2, 0.15, x2, sprintf('%3.1fU ——— Bolus Insulin ——— %3.1fU', ins_out_1(2), ins_out_2(2)), 'Color', bolus_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
        text(ax2, 0.15, x1, sprintf('%3.1fU ——— Basal Insulin ——— %3.1fU', ins_out_1(1), ins_out_2(1)), 'Color', basal_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');
    else
        ratio_ = 1.6;
        ax3 = subplot('Position', [graph_percent*1.01, 0.43, (1-graph_percent)*0.99, 0.48]);
        ax3.Tag = 'summary-glucose';

        hold(ax3, 'on');
        ax3.XLim = [0, 1];
        ax3.YLim = [0, 1];
        ax3.XAxis.Visible = 'off';
        ax3.YAxis.Visible = 'off';
        ax3.Color = 'none';

        for gr = 1:numel(subjGrp)
            text(ax3, (gr-1)/numel(subjGrp)/ratio_+0.05, 1.05, shortnames{gr}, 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
        end

        hypo2_color = [141, 45, 48]/255;
        hypo1_color = [200, 38, 47]/255;
        tir_color = [51, 162, 82]/255;
        hyper1_color = [229, 168, 41]/255;
        hyper2_color = [217, 123, 45]/255;
        colors = { ...
            hypo2_color; ...
            hypo1_color; ...
            tir_color; ...
            hyper1_color; ...
            hyper2_color; ...
            };

        cgm_out = [];
        for k = 1:numel(subjGrp)
            cgm_out(:, k) = [ ...
                mean(subjGrp{k}.getTimeIn(-inf, 54)); ...
                mean(subjGrp{k}.getTimeIn(54, 70)); ...
                mean(subjGrp{k}.getTimeIn(70, 180.5)); ...
                mean(subjGrp{k}.getTimeIn(180.5, 250)); ...
                mean(subjGrp{k}.getTimeIn(250.5, inf)); ...
                ];
            cgm_out(:, k) = round(cgm_out(:, k), 1);
        end

        b = bar(ax3, (0:numel(subjGrp)-1)/numel(subjGrp)/ratio_+0.05, cgm_out/100, 'stacked');

        for k = 1:length(b)
            b(k).FaceColor = colors{k};
            b(k).EdgeColor = [0.95, 0.95, 0.95];
            b(k).LineWidth = 1.0;
            b(k).BarWidth = 0.4;
            b(k).BaseLine.Visible = 'off';
        end

        for k = 1:numel(subjGrp)
            positions_ = cumsum(mean(cgm_out(:, k), 2)) / 100;
            x3 = mean(positions_(2:3));
            x4 = max(x3+0.06, mean(positions_(3:4)));
            x5 = max(x4+0.06, 1.02);
            x2 = min(x3-0.04, positions_(2));
            x1 = min(x2-0.12, -0.05);
            text(ax3, (k-1)/numel(subjGrp)/ratio_+0.085, x5, sprintf(' %3.1f %%', cgm_out(5, k)), 'Color', hyper2_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'top');
            text(ax3, (k-1)/numel(subjGrp)/ratio_+0.085, x4, sprintf(' %3.1f %%', cgm_out(4, k)), 'Color', hyper1_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
            text(ax3, (k-1)/numel(subjGrp)/ratio_+0.085, x3, sprintf(' %3.1f %%', cgm_out(3, k)), 'Color', tir_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
            text(ax3, (k-1)/numel(subjGrp)/ratio_+0.085, x2, sprintf(' %3.1f %%', cgm_out(2, k)), 'Color', hypo1_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
            text(ax3, (k-1)/numel(subjGrp)/ratio_+0.085, x1, sprintf(' %3.1f %%', cgm_out(1, k)), 'Color', hypo2_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');
        end
        text(ax3, (k-1)/numel(subjGrp)/ratio_+0.21, x5, ' —— >250 mg/dL', 'Color', hyper2_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'top');
        text(ax3, (k-1)/numel(subjGrp)/ratio_+0.21, x4, ' — 180–250 mg/dL', 'Color', hyper1_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
        text(ax3, (k-1)/numel(subjGrp)/ratio_+0.21, x3, ' — 70–180.0 mg/dL', 'Color', tir_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
        text(ax3, (k-1)/numel(subjGrp)/ratio_+0.21, x2, ' —— 54–70 mg/dL', 'Color', hypo1_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
        text(ax3, (k-1)/numel(subjGrp)/ratio_+0.21, x1, ' ——— <54 mg/dL', 'Color', hypo2_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');

        % insulin bars
        ax2 = subplot('Position', [graph_percent*1.01, 0.07, (1-graph_percent)*0.99, 0.3]);
        ax2.Tag = 'summary-insulin';

        hold(ax2, 'on');
        ax2.XLim = [0, 1];
        ax2.YLim = [0, 1];
        ax2.XAxis.Visible = 'off';
        ax2.YAxis.Visible = 'off';
        ax2.Color = 'none';

        basal_color = [51,102,255]/255;
        bolus_color = [119,170,255]/255;
        colors = { ...
            basal_color; ...
            bolus_color; ...
            };

        for k = 1:numel(subjGrp)
            ins_out(:, k) = [ ...
                mean(subjGrp{k}.getTotalBasal())/days(duration_); ...
                mean(subjGrp{k}.getTotalBolus())/days(duration_); ...
                ];
            ins_out(:, k) = round(ins_out(:, k), 1);
        end

        b = bar(ax2, (0:numel(subjGrp)-1)/numel(subjGrp)/ratio_+0.05, ins_out/(10*round(max(sum(ins_out))*1.1/10)), 'stacked');

        for k = 1:length(b)
            b(k).FaceColor = colors{k};
            b(k).EdgeColor = [0.95, 0.95, 0.95];
            b(k).LineWidth = 1.0;
            b(k).BarWidth = 0.4;
            b(k).BaseLine.Visible = 'off';
        end

        for k = 1:numel(subjGrp)
            positions_ = cumsum(mean(ins_out(:, k), 2))/(10*round(max(sum(ins_out))*1.1/10));
            x2 = mean(positions_(1:2));
            x1 = positions_(1)*0.5;
            text(ax2, (k-1)/numel(subjGrp)/ratio_+0.085, x2, sprintf(' %3.1fU', ins_out(2, k)), 'Color', bolus_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
            text(ax2, (k-1)/numel(subjGrp)/ratio_+0.085, x1, sprintf(' %3.1fU', ins_out(1, k)), 'Color', basal_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');
        end
        text(ax2, (k-1)/numel(subjGrp)/ratio_+0.21, x2, '—— Bolus Insulin', 'Color', bolus_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
        text(ax2, (k-1)/numel(subjGrp)/ratio_+0.21, x1, '—— Basal Insulin', 'Color', basal_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');
    end
end

if separate_fig_
    fig = {fig1, fig2};
else
    fig = fig1;
end

end

