function [fig, analyzedGrp] = plotCompare(subjGrp, varargin)

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
    [220, 120, 227]/256, ... % pink
    [128, 151, 158]/256, ... % gray
    [119, 170, 255]/256, ... % light blue
    [51, 162, 82]/256, ... % green
    [255, 127, 14]/256, ... % orange
    [255, 187, 120]/256, ... % light orange
    [200, 38, 47]/256, ... %, ... % red
    [141, 45, 48]/256, ... % dark red
    };
linestyle = {'-', '-', '-', '-', '-', '-', '-', '-'};
names = cellfun(@(c)(strcat('subj', num2str(c))), num2cell(1:length(subjGrp)), 'UniformOutput', false);
shortnames = {};
international_units = false;
titleString = 'default';
separate_fig_ = false;
error_bars_type_ = 'iqr';
detailed_outcomes = false;
graph_percent = 0.65;
show_insulin = true;
bolus_type = 'all'; % 'all', 'carb', 'bps', 'corr'
insulin_time_step = 2*60; % minutes
plot_start_time = 0;
cgm_outcomes_opt = [];
metrics = { 'tar1', 'tar2', 'tir', 'ttir', 'tbr1', 'tbr2', ...
    'ntar', 'ntir', 'ntbr', ...
    'dtar', 'dtir', 'dtbr', ...
    'avgg', 'sdg', 'cvg', ...
    'gmi', 'lbgi', 'hbgi', 'bgi', ...
    'tdi', 'tdba', 'tdbo', 'ntdbo',...
    'carb', 'carbcount', 'carbann', 'treat'};
for nVar = 1:2:length(varargin)
    switch lower(varargin{nVar})
        case {'name', 'names', 'legend', 'arms'}
            names = strrep(varargin{nVar+1}, '_', ' ');
        case {'shortname', 'shortnames', 'shortlegend'}
            shortnames = varargin{nVar+1};
        case {'colors', 'color'}
            colors = varargin{nVar+1};
        case {'linestyle', 'line'}
            linestyle = varargin{nVar+1};
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
        case {'bolustype', 'bolus_type', 'bolusrule', 'bolus_rule'}
            bolus_type = varargin{nVar+1};
        case {'insulintimestep', 'insulin_timestep', 'insulinstep', 'insulin_step', 'insulin_dt'}
            insulin_time_step = varargin{nVar+1};
        case 'graphpercent'
            graph_percent = varargin{nVar+1};
        case {'metric', 'metrics'}
            metrics = varargin{nVar+1};
        case {'thermo_outcomes', 'thermo_out', 'cgm_outcomes', 'cgm_out'}
            cgm_outcomes_opt = varargin{nVar+1};
    end
end
if isempty(shortnames)
    shortnames = names;
    for gr = 1:length(shortnames)
        if length(shortnames{gr}) > 20
            shortnames{gr} = shortnames{gr}(1:20);
        end
    end
end

subjGrpAll = [subjGrp{:}];

% Force insulin overlays off when both insulin streams are unavailable.
if show_insulin
    hasBasalRate = any(arrayfun(@(s) istimetable(s.basalRate) && ~isempty(s.basalRate), subjGrpAll));
    hasBolus = any(arrayfun(@(s) istimetable(s.bolus) && ~isempty(s.bolus), subjGrpAll));
    if ~(hasBasalRate || hasBolus)
        show_insulin = false;
    end
end

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

% Store original names for title
names_for_title = names;

for kk = 1:length(names)
    names{kk} = sprintf('\\color[rgb]{%1.2f,%1.2f,%1.2f}%s', colors{kk}, names{kk});
end

clf(fig1);
if ~detailed_outcomes
    ax0 = subplot('Position', [0.05, 0.12, graph_percent*0.95-0.05, 0.82]);
else
    if separate_fig_
        ax0 = subplot('Position', [0.05, 0.15, 0.90, 0.82]);
    else
        ax0 = subplot('Position', [0.05, 0.15, graph_percent*0.99-0.05, 0.82]);
    end
end
ax0.Tag = 'plot';

cla(ax0);
hold(ax0, 'on');
set(ax0, 'FontWeight', 'bold', 'LineWidth', 2.0, 'FontSize', 14);

% make sure subjGrp has different names
for gr = numel(subjGrp):-1:1
    for k = 1:length(subjGrp{gr})
        subjGrp{gr}(k).name = sprintf('gr%d_%s', gr, subjGrp{gr}(k).name);
    end
end

stepTime_ = 5;
analyzedGrp = cell(size(subjGrp));
popSize = [];
for gr = numel(subjGrp):-1:1
    if days(mode([subjGrpAll.duration])) < 1
        offset_ = 0.0;
    else
        offset_ = floor(nanmedian([[subjGrpAll.startTimeInMinutes], mod(round([subjGrpAll.endTimeInMinutes]+stepTime_), 1440)]/60.0))/24.0;
    end

    obj = subjGrp{gr}.copy();

    % convert to days
    if nanmedian(days([obj.duration])) < 1
        idx2Remove = days([obj.duration]) < 0.75*nanmedian(days([obj.duration])) | isnan(days([obj.duration]));
        analyzedGrp{gr} = obj(~idx2Remove);
        uniqueIDS = unique(cellfun(@(c)c{1}, cellfun(@(c)strsplit(c, '#'), {obj.name}, 'UniformOutput', false), 'UniformOutput', false));
        popSize(gr) = numel(uniqueIDS);
    else
        objDays = obj.getDays(-offset_);
        if iscell(objDays)
            obj = [objDays{:}];
        else
            obj = objDays;
        end
        obj([obj.durationCGM] < 0.7) = [];
        uniqueIDS = unique(cellfun(@(c)c{1}, cellfun(@(c)strsplit(c, '#'), {obj.name}, 'UniformOutput', false), 'UniformOutput', false));
        for k = 1:length(uniqueIDS)
            analyzedGrp{gr}(end+1) = DIAX.merge(obj(contains({obj.name}, uniqueIDS{k})));
        end
        popSize(gr) = numel(uniqueIDS);
    end

    data = obj.getSampledData(stepTime_, 'fields', {});
    duration_ = median([data.duration]);
    if days(duration_) <= 1
        duration_ = hours(round(hours(duration_)));
    else
        duration_ = days(1);
    end
    data = obj.getSampledData(stepTime_, 'fields', {'cgm', 'basalRate', 'bolus', 'bolusCarb'}, 'duration', duration_);

    % time
    startTime_ = mode([data.startTime]);
    t = mean([data.time], 2) + startTime_;
    if duration_ <= days(1)
        t_plot = startTime_ + (0:stepTime_:hours(duration_)*60-stepTime_);
        idxOrdred = 1:1:hours(duration_)*60/stepTime_;
    else
        t_plot = 0:stepTime_:1440-stepTime_ + plot_start_time;
        [~, idxOrdred] = ismember(mod(t_plot, 1440), mod(t, 1440));
    end

    % targets
    % plot(ax0, [t_plot(1)-1000, t_plot(end)+1000], [250.0, 250.0], '-k', 'LineWidth', 0.5);
    plot(ax0, [t_plot(1)-1000, t_plot(end)+1000], [180.0, 180.0], '-k', 'LineWidth', 0.5);
    plot(ax0, [t_plot(1)-1000, t_plot(end)+1000], [70.0, 70.0], '-k', 'LineWidth', 0.5);
    % plot(ax0, [t_plot(1)-1000, t_plot(end)+1000], [54.0, 54.0], '-k', 'LineWidth', 0.5);

    % cgm
    cgm.mean = mean([data.cgm], 2, 'omitnan');
    cgm.median = median([data.cgm], 2, 'omitnan');
    cgm.std = std([data.cgm], [], 2, 'omitnan');
    cgm.iqr05 = prctile([data.cgm], 05, 2);
    cgm.iqr25 = prctile([data.cgm], 25, 2);
    cgm.iqr75 = prctile([data.cgm], 75, 2);
    cgm.iqr95 = prctile([data.cgm], 95, 2);

    % create cgm_plot with corect order
    cgm_plot.mean = cgm.mean(idxOrdred);
    cgm_plot.median = cgm.median(idxOrdred);
    cgm_plot.std = cgm.std(idxOrdred);
    cgm_plot.iqr05 = cgm.iqr05(idxOrdred);
    cgm_plot.iqr25 = cgm.iqr25(idxOrdred);
    cgm_plot.iqr75 = cgm.iqr75(idxOrdred);
    cgm_plot.iqr95 = cgm.iqr95(idxOrdred);

    % smooth mean/median/percentiles
    smoothing_window = 7;
    pad = floor(smoothing_window/2);
    fields = {'mean', 'median', 'iqr05', 'iqr25', 'iqr75', 'iqr95'};
    for f = 1:numel(fields)
        v = cgm_plot.(fields{f});
        v_pad = [v(end-pad+1:end); v; v(1:pad)];
        v_smooth = smoothdata(v_pad, 'movmean', smoothing_window);
        cgm_plot.(fields{f}) = v_smooth(pad+1:end-pad);
    end

    % remove all nan
    idx2Remove = isnan(cgm_plot.mean);
    cgm_plot.mean(idx2Remove) = [];
    cgm_plot.median(idx2Remove) = [];
    cgm_plot.std(idx2Remove) = [];
    cgm_plot.iqr05(idx2Remove) = [];
    cgm_plot.iqr25(idx2Remove) = [];
    cgm_plot.iqr75(idx2Remove) = [];
    cgm_plot.iqr95(idx2Remove) = [];
    t_plot(idx2Remove) = [];

    if strcmp(error_bars_type_, 'iqr')
        plot(ax0, t_plot, cgm_plot.iqr25, ...
            'Color', colors{gr}, ...
            'LineWidth', 1.0, ...
            'LineStyle', '-', ...
            'Marker', 'none', ...
            'MarkerSize', 8);
        plot(ax0, t_plot, cgm_plot.iqr75, ...
            'Color', colors{gr}, ...
            'LineWidth', 1.0, ...
            'LineStyle', '-', ...
            'Marker', 'none', ...
            'MarkerSize', 8);
        patch(ax0, 'XData', [t_plot, fliplr(t_plot)], ...
            'YData', [cgm_plot.iqr25', fliplr(cgm_plot.iqr75')], ...
            'EdgeColor', 'none', ...
            'FaceColor', colors{gr}, ...
            'FaceAlpha', .1);
    elseif strcmp(error_bars_type_, 'patch')
        plot(ax0, t_plot, cgm_plot.iqr05, ...
            'Color', colors{gr}, ...
            'LineWidth', 0.5, ...
            'LineStyle', '-', ...
            'Marker', 'none', ...
            'MarkerSize', 8);
        plot(ax0, t_plot, cgm_plot.iqr95, ...
            'Color', colors{gr}, ...
            'LineWidth', 0.5, ...
            'LineStyle', '-', ...
            'Marker', 'none', ...
            'MarkerSize', 8);
        patch(ax0, 'XData', [t_plot, fliplr(t_plot)], ...
            'YData', [cgm_plot.iqr05', fliplr(cgm_plot.iqr95')], ...
            'EdgeColor', colors{gr}, ...
            'FaceColor', colors{gr}, ...
            'FaceAlpha', .1);
    end
    PLOTNAME(gr) = plot(ax0, t_plot, cgm_plot.median, ...
        'Color', colors{gr}, ...
        'LineWidth', 4.0, ...
        'LineStyle', linestyle{gr}, ...
        'Marker', 'none', ...
        'MarkerSize', 8);

    xlim(ax0, [t_plot(1) - 30, t_plot(end) + 30]);
    if t_plot(end) - t_plot(1) <= 2 * 60
        sTick = 0.5 * 60;
    elseif t_plot(end) - t_plot(1) <= 8 * 60
        sTick = 1 * 60;
    elseif t_plot(end) - t_plot(1) <= 24 * 60
        sTick = 2 * 60;
    elseif t_plot(end) - t_plot(1) <= 48 * 60
        sTick = 4 * 60;
    elseif t_plot(end) - t_plot(1) <= 5 * 24 * 60
        sTick = 12 * 60;
    elseif t_plot(end) - t_plot(1) <= 8 * 7 * 24 * 60
        sTick = 24 * 60;
    else
        sTick = 7 * 24 * 60;
    end
    st_ = 0.0;
    if sTick < 1440
        xticks(ax0, (sTick * floor((t_plot(1) + st_) / sTick):sTick:sTick * ceil((t_plot(end) + st_) / sTick)));
        xticklabels(ax0, [num2str(mod((sTick / 60 * floor((t_plot(1) + st_) / sTick):sTick / 60:sTick / 60 * ceil((t_plot(end) + st_) / sTick)), 24)'), repmat(':00', length(sTick / 60 * floor((t_plot(1) + st_) / sTick):sTick / 60:sTick / 60 * ceil((t_plot(end) + st_) / sTick)), 1)]);
        ax0.XLabel.String = 'Time (HH:MM)';
    else
        xticks(ax0, t_plot(1):sTick:t_plot(end));
        xticklabels(ax0, ((sTick * floor((t_plot(1) + st_) / sTick):sTick:sTick * ceil((t_plot(end) + st_) / sTick)) - st_) / 1440);
        ax0.XLabel.String = 'Time (days)';
    end

    if show_insulin
        ylim(ax0, [0, 300]);
    else
        ylim(ax0, [40, 300]);
    end
    yticks(ax0, [0, 40, 70, 120, 180, 250, 300]);
    if international_units
        ax0.YLabel.String = 'Sensor Glucose (mmol/L)';
        yticklabels(ax0, [0, 2.2, 3.9, 6.7, 10.0, 13.9, 16.7]);
    else
        ax0.YLabel.String = 'Sensor Glucose (mg/dl)';
    end

    if show_insulin
        tts = insulin_time_step/stepTime_;

        % Split basal and bolus before aggregating to the plotting granularity
        switch bolus_type
            case 'all'
                basal_u = [data.basalRate]/12.0; % convert U/hr to U per 5 min
                bolus_u = [data.bolus];
            case 'carb'
                basal_u = [data.basalRate]/12.0 + max([data.bolus] - [data.bolusCarb], 0); % convert U/hr to U per 5 min
                bolus_u = [data.bolusCarb];
            otherwise
                error('Unknown rule for bolus_type %s', bolus_type);
        end

        if size(basal_u, 2) == 1
            basal_u_h = tts*mean(reshape(basal_u, tts, (minutes(duration_)/stepTime_)/tts), 1, 'omitnan')';
            bolus_u_h = tts*mean(reshape(bolus_u, tts, (minutes(duration_)/stepTime_)/tts), 1, 'omitnan')';
        else
            basal_u_h = tts*squeeze(mean(reshape(basal_u, tts, (minutes(duration_)/stepTime_)/tts, []), 1, 'omitnan'));
            bolus_u_h = tts*squeeze(mean(reshape(bolus_u, tts, (minutes(duration_)/stepTime_)/tts, []), 1, 'omitnan'));
        end

        if days(mode([subjGrpAll.duration])) < 1
            tbarate = startTime_ + (0:stepTime_*tts:hours(duration_)*60-stepTime_*tts);
        else
            tbarate = 0:stepTime_*tts:1440-stepTime_*tts + plot_start_time;
        end
        tbarate = tbarate(:);

        if days(mode([subjGrpAll.duration])) < 1
            idxOrdred = 1:1:(minutes(duration_)/stepTime_)/tts;
        else
            [~, idxOrdred] = ismember(mod(tbarate, 1440), mod(t(1:tts:end), 1440));
        end

        % basal rate
        yyaxis(ax0, 'right');
        % create basal/bolus with correct order
        basal_.mean = mean(basal_u_h, 2, 'omitnan');
        bolus_.mean = mean(bolus_u_h, 2, 'omitnan');
        % create basal/bolus with correct order
        basal_plot.mean = basal_.mean(idxOrdred);
        bolus_plot.mean = bolus_.mean(idxOrdred);

        % Calculate bar offset and width to avoid overlap
        nGroups = numel(subjGrp);
        barSpacing = 0.25 * (nGroups / 2) * stepTime_ * tts; % e.g., 10*5 = 50
        maxBarWidth = 0.25 * barSpacing / nGroups; % leave some space between groups
        barOffset = linspace(-barSpacing/2 + maxBarWidth/2, barSpacing/2 - maxBarWidth/2, nGroups);

        b = bar(ax0, tbarate + barOffset(gr) + stepTime_ * tts / 2, [basal_plot.mean, bolus_plot.mean], ...
            'stacked', ...
            'EdgeColor', 'none', ...
            'FaceColor', colors{gr}, ...
            'BarWidth', 0.15);
        b(2).FaceAlpha = 0.7;

        ax0.YAxis(2).Color = [0, 0, 0];
        ax0.YLabel.String = 'Insulin (U)';
        ax0.YLim = [0, 30];
        ax0.YTick = (0:2:40);

        yyaxis(ax0, 'left');
        ax0.YAxis(2).Color = [0, 0, 0];
    end
end

if strcmp(titleString, 'default')
    for gr = numel(subjGrp):-1:1
        text_{gr} = sprintf('\\color[rgb]{%1.2f,%1.2f,%1.2f}%s (n=%d)', colors{gr}, names_for_title{gr}, popSize(gr));
    end
    % Calculate duration in days
    median_duration_days = round(median(days([analyzedGrp{1}.duration])));
    title(ax0, sprintf('%s for %d days', strjoin(text_, ' vs '), median_duration_days), 'FontSize', 16, 'Interpreter', 'tex');
else
    title(ax0, titleString, 'FontSize', 16, 'Interpreter', 'tex');
end

names_ = {};
for gr = numel(subjGrp):-1:1
    names_{gr} = sprintf('%s (n=%d)', names{gr}, popSize(gr));
end

legend(PLOTNAME, names_, 'location', 'northwest', 'box', 'off');

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

if detailed_outcomes
    if separate_fig_
        ax1 = subplot('Position', [0.05, 0.05, 0.90, 0.90]);
    else
        ax1 = subplot('Position', [graph_percent*1.0, 0.15, (1-graph_percent)*0.99, 0.70]);
    end

    ax1 = Subject.compareMetrics(analyzedGrp, 'metrics', metrics, 'ax', ax1, 'names', shortnames, 'colors', colors);
else
    if numel(analyzedGrp) == 2
        if show_insulin
            ax3 = subplot('Position', [graph_percent*1.01+0.03, 0.42, 1-graph_percent/1.01-0.07, 0.45]);
        else
            ax3 = subplot('Position', [graph_percent*1.01, 0.18, 1-graph_percent/1.01-0.04, 0.65]);
        end
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
        colors_thermo = { ...
            hypo2_color; ...
            hypo1_color; ...
            tir_color; ...
            hyper1_color; ...
            hyper2_color; ...
            };

        text(ax3, 0.12, 1.14, shortnames{1}, 'Color', colors{1}, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'FontSize', 13);
        text(ax3, 0.85, 1.14, shortnames{2}, 'Color', colors{2}, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'FontSize', 13);

        if ~isempty(cgm_outcomes_opt)
            cgm_out_1 = round(flipud(cgm_outcomes_opt(:, 1)), 1);
            cgm_out_2 = round(flipud(cgm_outcomes_opt(:, 2)), 1);
        else
            cgm_out_1 = [ ...
                mean(analyzedGrp{1}.getTimeIn(-inf, 54)); ...
                mean(analyzedGrp{1}.getTimeIn(54, 70)); ...
                mean(analyzedGrp{1}.getTimeIn(70, 180.5)); ...
                mean(analyzedGrp{1}.getTimeIn(180.5, 250)); ...
                mean(analyzedGrp{1}.getTimeIn(250.5, inf)); ...
                ];
            cgm_out_1 = round(cgm_out_1, 1);
            cgm_out_2 = [ ...
                mean(analyzedGrp{2}.getTimeIn(-inf, 54)); ...
                mean(analyzedGrp{2}.getTimeIn(54, 70)); ...
                mean(analyzedGrp{2}.getTimeIn(70, 180.5)); ...
                mean(analyzedGrp{2}.getTimeIn(180.5, 250)); ...
                mean(analyzedGrp{2}.getTimeIn(250.5, inf)); ...
                ];
            cgm_out_2 = round(cgm_out_2, 1);
        end
        cgm_out_ = [cgm_out_1 cgm_out_2];

        b = bar(ax3, [0.1 0.9], cgm_out_/100, 'stacked', 'BarWidth', 0.05);

        for k = 1:length(cgm_out_1)
            b(k).FaceColor = colors_thermo{k};
            b(k).EdgeColor = [0.95, 0.95, 0.95];
            b(k).LineWidth = 1.0;
            b(k).BarWidth = 0.15;
            b(k).BaseLine.Visible = 'off';
        end

        positions_ = cumsum(mean(cgm_out_1, 2)) / 100;
        x3 = mean(positions_(2:3));
        x4 = max(x3+0.06, mean(positions_(3:4)));
        x5 = max(x4+0.06, 1.02);
        x2 = min(x3, mean(positions_(1:2)))+0.02;
        x1 = min(x2-0.10, -0.05);
        x_offset_ = 0.16;
        text(ax3, x_offset_, x5, sprintf('  %3.1f %% —— >250 mg/dL —— %3.1f %%  ', cgm_out_1(5), cgm_out_2(5)), 'Color', hyper2_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'top', 'HorizontalAlignment', 'left');
        text(ax3, x_offset_, x4, sprintf(' %3.1f %% — 180–250 mg/dL — %3.1f %%  ', cgm_out_1(4), cgm_out_2(4)), 'Color', hyper1_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left');
        text(ax3, x_offset_, x3, sprintf(' %3.1f %% — 70–180.0 mg/dL — %3.1f %%  ', cgm_out_1(3), cgm_out_2(3)), 'Color', tir_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left');
        text(ax3, x_offset_, x2, sprintf('  %3.1f %% —— 54–70 mg/dL —— %3.1f %%  ', cgm_out_1(2), cgm_out_2(2)), 'Color', hypo1_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left');
        text(ax3, x_offset_, x1, sprintf('%3.1f %% ——— <54 mg/dL ——— %3.1f %%  ', cgm_out_1(1), cgm_out_2(1)), 'Color', hypo2_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'left');

        % insulin bars
        if show_insulin
            ax2 = subplot('Position', [graph_percent*1.01+0.03, 0.05, 1-graph_percent/1.01-0.07, 0.30]);
            ax2.Tag = 'summary-insulin';

            hold(ax2, 'on');
            ax2.XLim = [0, 1];
            ax2.YLim = [0, 1];
            ax2.XAxis.Visible = 'off';
            ax2.YAxis.Visible = 'off';
            ax2.Color = 'none';

            basal_color = [51,102,255]/255;
            bolus_color = [119,170,255]/255;
            colors_insulin = { ...
                basal_color; ...
                bolus_color; ...
                };

            ins_out = zeros(2,2);
            for k = 1:2
                switch bolus_type
                    case 'all'
                        total_basal = analyzedGrp{k}.getTotalBasal();
                        total_bolus = analyzedGrp{k}.getTotalBolus();
                    case 'carb'
                        total_basal = analyzedGrp{k}.getTotalBasal() + analyzedGrp{k}.getTotalBolus() - analyzedGrp{k}.getTotalCarbBolus();
                        total_bolus = analyzedGrp{k}.getTotalCarbBolus();
                    otherwise
                        error('Unknown rule for bolus_type %s', bolus_type);
                end
                if days([analyzedGrp{k}.duration]) < 0.95
                    ins_out(:,k) = [ ...
                        mean(total_basal); ...
                        mean(total_bolus); ...
                        ];
                else
                    ins_out(:,k) = [ ...
                        mean(total_basal./days([analyzedGrp{k}.duration])); ...
                        mean(total_bolus./days([analyzedGrp{k}.duration])); ...
                        ];
                end
                ins_out(:,k) = round(ins_out(:,k), 1);
            end

            b = bar(ax2, [0.1 0.9], ins_out'/(10*round(max(sum(ins_out))*1.1/10)), 'stacked', 'BarWidth', 0.05);

            for k = 1:2
                b(k).FaceColor = colors_insulin{k};
                b(k).EdgeColor = [0.95, 0.95, 0.95];
                b(k).LineWidth = 1.0;
                b(k).BarWidth = 0.15;
                b(k).BaseLine.Visible = 'off';
            end

            positions_ = cumsum(mean(ins_out, 2))/(10*round(max(sum(ins_out))*1.1/10));
            x2 = mean(positions_(1:2));
            x1 = positions_(1)*0.5;
            x_offset_ = 0.50;
            text(ax2, x_offset_, x2, sprintf('%3.1fU —— Bolus Insulin —— %3.1fU', ins_out(2,1), ins_out(2,2)), 'Color', bolus_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle', 'HorizontalAlignment', 'center');
            text(ax2, x_offset_, x1, sprintf('%3.1fU —— Basal Insulin —— %3.1fU', ins_out(1,1), ins_out(1,2)), 'Color', basal_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center');
        end
    else
        ratio_ = 1.6;%((numel(analyzedGrp)-1)/numel(analyzedGrp))/0.55;
        if show_insulin
            ax3 = subplot('Position', [graph_percent*1.01, 0.43, (1-graph_percent)*0.99, 0.48]);
        else
            ax3 = subplot('Position', [graph_percent*1.01+0.02, 0.22, (1-graph_percent)*0.99, 0.62]);
        end
        ax3.Tag = 'summary-glucose';

        hold(ax3, 'on');
        ax3.XLim = [0, 1];
        ax3.YLim = [0, 1];
        ax3.XAxis.Visible = 'off';
        ax3.YAxis.Visible = 'off';
        ax3.Color = 'none';

        for gr = 1:numel(analyzedGrp)
            text(ax3, (gr-1)/numel(analyzedGrp)/ratio_+0.07, 1.1, shortnames{gr}, 'Color', colors{gr}, 'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
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

        if ~isempty(cgm_outcomes_opt)
            cgm_out = round(flipud(cgm_outcomes_opt), 1);
        else
            cgm_out = [];
            for k = 1:numel(analyzedGrp)
                cgm_out(:, k) = [ ...
                    mean(analyzedGrp{k}.getTimeIn(-inf, 54)); ...
                    mean(analyzedGrp{k}.getTimeIn(54, 70)); ...
                    mean(analyzedGrp{k}.getTimeIn(70, 180.5)); ...
                    mean(analyzedGrp{k}.getTimeIn(180.5, 250)); ...
                    mean(analyzedGrp{k}.getTimeIn(250.5, inf)); ...
                    ];
                cgm_out(:, k) = round(cgm_out(:, k), 1);
            end
        end

        b = bar(ax3, (0:numel(analyzedGrp)-1)/numel(analyzedGrp)/ratio_+0.05, cgm_out'/100, 'stacked');

        for k = 1:length(b)
            b(k).FaceColor = colors{k};
            b(k).EdgeColor = [0.95, 0.95, 0.95];
            b(k).LineWidth = 1.0;
            b(k).BarWidth = 0.4;
            b(k).BaseLine.Visible = 'off';
        end

        for k = 1:numel(analyzedGrp)
            positions_ = cumsum(mean(cgm_out(:, k), 2)) / 100;
            x3 = mean(positions_(2:3));
            x4 = max(x3+0.06, mean(positions_(3:4)));
            x5 = max(x4+0.06, 1.02);
            x2 = min(x3-0.04, positions_(2));
            x1 = min(x2-0.12, -0.05);
            text(ax3, (k-1)/numel(analyzedGrp)/ratio_+0.085, x5, sprintf(' %3.1f %%', cgm_out(5, k)), 'Color', hyper2_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'top');
            text(ax3, (k-1)/numel(analyzedGrp)/ratio_+0.085, x4, sprintf(' %3.1f %%', cgm_out(4, k)), 'Color', hyper1_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
            text(ax3, (k-1)/numel(analyzedGrp)/ratio_+0.085, x3, sprintf(' %3.1f %%', cgm_out(3, k)), 'Color', tir_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
            text(ax3, (k-1)/numel(analyzedGrp)/ratio_+0.085, x2, sprintf(' %3.1f %%', cgm_out(2, k)), 'Color', hypo1_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
            text(ax3, (k-1)/numel(analyzedGrp)/ratio_+0.085, x1, sprintf(' %3.1f %%', cgm_out(1, k)), 'Color', hypo2_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');
        end
        positions_ = cumsum(mean(cgm_out, 2)) / 100;
        x3 = mean(positions_(2:3));
        x4 = max(x3+0.06, mean(positions_(3:4)));
        x5 = max(x4+0.06, 1.02);
        x2 = min(x3-0.04, positions_(2));
        x1 = min(x2-0.12, -0.05);
        text(ax3, (k-1)/numel(analyzedGrp)/ratio_+0.19, x5, ' —— >250 mg/dL', 'Color', hyper2_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'top');
        text(ax3, (k-1)/numel(analyzedGrp)/ratio_+0.19, x4, ' — 180–250 mg/dL', 'Color', hyper1_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
        text(ax3, (k-1)/numel(analyzedGrp)/ratio_+0.19, x3, ' — 70–180.0 mg/dL', 'Color', tir_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
        text(ax3, (k-1)/numel(analyzedGrp)/ratio_+0.19, x2, ' —— 54–70 mg/dL', 'Color', hypo1_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
        text(ax3, (k-1)/numel(analyzedGrp)/ratio_+0.19, x1, ' ——— <54 mg/dL', 'Color', hypo2_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');

        % insulin bars
        if show_insulin
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

            for k = 1:numel(analyzedGrp)
                if analyzedGrp{k}.getTotalCarbBolus() == 0
                    total_basal = analyzedGrp{k}.getTotalBasal();
                    total_bolus = analyzedGrp{k}.getTotalBolus();
                else
                    total_basal = analyzedGrp{k}.getTotalBasal() + analyzedGrp{k}.getTotalCorrBolus();
                    total_bolus = analyzedGrp{k}.getTotalCarbBolus();
                end
                if days([analyzedGrp{k}.duration]) < 0.9
                    ins_out(:, k) = [ ...
                        mean(total_basal); ...
                        mean(total_bolus); ...
                        ];
                else
                    ins_out(:, k) = [ ...
                        mean(total_basal./ceil(days([analyzedGrp{k}.durationCGM]))); ...
                        mean(total_bolus./ceil(days([analyzedGrp{k}.durationCGM]))); ...
                        ];
                end
                ins_out(:, k) = round(ins_out(:, k), 1);
            end

            b = bar(ax2, (0:numel(analyzedGrp)-1)/numel(analyzedGrp)/ratio_+0.05, ins_out/(10*round(max(sum(ins_out))*1.1/10)), 'stacked');

            for k = 1:length(b)
                b(k).FaceColor = colors{k};
                b(k).EdgeColor = [0.95, 0.95, 0.95];
                b(k).LineWidth = 1.0;
                b(k).BarWidth = 0.4;
                b(k).BaseLine.Visible = 'off';
            end

            for k = 1:numel(analyzedGrp)
                positions_ = cumsum(mean(ins_out(:, k), 2))/(10*round(max(sum(ins_out))*1.1/10));
                x2 = mean(positions_(1:2));
                x1 = positions_(1)*0.5;
                text(ax2, (k-1)/numel(analyzedGrp)/ratio_+0.085, x2, sprintf(' %3.1fU', ins_out(2, k)), 'Color', bolus_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
                text(ax2, (k-1)/numel(analyzedGrp)/ratio_+0.085, x1, sprintf(' %3.1fU', ins_out(1, k)), 'Color', basal_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');
            end
            positions_ = cumsum(mean(ins_out, 2))/(10*round(max(sum(ins_out))*1.1/10));
            x2 = mean(positions_(1:2));
            x1 = positions_(1)*0.5;
            text(ax2, (k-1)/numel(analyzedGrp)/ratio_+0.19, x2, '—— Bolus Insulin', 'Color', bolus_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
            text(ax2, (k-1)/numel(analyzedGrp)/ratio_+0.19, x1, '—— Basal Insulin', 'Color', basal_color, 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');
        end
    end
end

if separate_fig_
    fig = {fig1, fig2};
else
    fig = fig1;
end

end

