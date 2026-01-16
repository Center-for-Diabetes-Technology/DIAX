function [ax1, tabMetrics] = compareMetrics(subjGrp, varargin)

if ~iscell(subjGrp)
    subjGrp = {subjGrp};
end

names = cellfun(@(c)(strcat('subj', num2str(c))), num2cell(1:length(subjGrp)), 'UniformOutput', false);
shortnames = {};
colors = {...
    [0.4660, 0.6740, 0.1880], ...
    [0.8500, 0.3250, 0.0980], ...
    [0.9290, 0.6940, 0.1250], ...
    [0.4940, 0.1840, 0.5560], ...
    [0, 0.4470, 0.7410], ...
    [0.3010, 0.7450, 0.9330], ...
    [0.6350, 0.0780, 0.1840]};
ax1 = 0;
metrics = {'tar1', 'tar2', 'tir', 'titr', 'tbr1', 'tbr2', ...
    'ntar', 'ntir', 'ntbr', ...
    'dtar', 'dtir', 'dtbr', ...
    'avgg', 'sdg', 'cvg', ...
    'gmi', 'lbgi', 'hbgi', 'bgi', ...
    'tdi', 'tdba', 'tdbo', 'tdcbo', 'ntdbo', 'ntdcbo', ...
    'carb', 'carbcount', 'carbann', 'treat'};
groups = {
    {'tar1', 'tar2', 'tir', 'titr', 'tbr1', 'tbr2'}, ...
    {'ntar', 'ntir', 'ntbr'}, ...
    {'dtar', 'dtir', 'dtbr'}, ...
    {'avgg', 'sdg', 'cvg'}, ...
    {'avgfast', 'sdfast', 'cvfast'}, ...
    {'gmi', 'lbgi', 'hbgi', 'bgi'}, ...
    {'tdi', 'tdba', 'tdbo', 'tdcbo', 'ntdbo', 'ntdcbo'}, ...
    {'carb', 'carbcount', 'carbann', 'treat'}, ...
    };

for nVar = 1:2:length(varargin)
    switch lower(varargin{nVar})
        case {'name', 'names', 'legend', 'arms'}
            names = strrep(varargin{nVar+1}, '_', ' ');
        case {'shortname', 'shortnames', 'shortlegend'}
            shortnames = varargin{nVar+1};
        case {'ax', 'axes'}
            ax1 = varargin{nVar+1};
        case {'color', 'colors'}
            colors = varargin{nVar+1};
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

if ~isa(ax1, 'matlab.graphics.axis.Axes')
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
    ax1 = axes; % Create a new axis
end

    % Helper functions
    function writeAverageInfo(infoArray, col, metricName)
        meanVal = mean(infoArray, "omitnan");
        stdVal = std(infoArray, [], 'omitnan');
        text(ax1, marginX + posX + (col-1)*offset, linePos(line, spacer), ...
            sprintf('%4.2f (%4.2f)', meanVal, stdVal), 'Color', 'k', 'FontSize', 12);

        % Store values in a struct to later convert to table
        if ~exist('table_dat', 'var') || isempty(table_dat) || ~ismember(metricName, table_dat.Properties.RowNames)
            if numel(subjGrp) == 2
                table_dat(metricName, :) = array2table(repmat({''}, 1, numel(shortnames)+2), 'VariableNames', {shortnames{:}, 'ETD', 'PValue'});
            else
                table_dat(metricName, :) = array2table(repmat({''}, 1, numel(shortnames)), 'VariableNames', shortnames);
            end
        end
        table_dat{metricName, shortnames{col}} = {sprintf('%4.2f (%4.2f)', meanVal, stdVal)};
    end


    function writeDifference(info1, info2, metricName)
        if length(info1) ~= length(info2)
            [~, pValue, ~, stats] = ttest2(info1, info2);
            diffVal = mean(info2, "omitnan") - mean(info1, "omitnan");
        else
            [~, pValue, ~, stats] = ttest(info1, info2);
            diffVal = mean(info2 - info1, "omitnan");
        end
        ci = diffVal + tinv([0.025 0.975], stats.df) * stats.sd / sqrt(length(info1));
        diffText = sprintf('%4.2f', diffVal);
        ciText = sprintf('[%4.2f, %4.2f]', ci(1), ci(2));
        pValueText = sprintf('P=%4.2f', pValue);
        text(ax1, marginX + posX + 2*offset, linePos(line, spacer), ...
            sprintf('%s %s %s)', diffText, ciText, pValueText), 'Color', 'k', 'FontSize', 12);

        % Store difference values
        table_dat(metricName, 'ETD') = {sprintf('%s %s', diffText, ciText)};
        table_dat(metricName, 'PValue') = {sprintf('P=%4.2f', pValue)};
    end

ax1.Tag = 'summary';

table_dat = table;

hold(ax1, 'on');
ax1.XLim = [0, 1];
ax1.YLim = [0, 1];
ax1.XAxis.Visible = 'off';
ax1.YAxis.Visible = 'off';
ax1.Color = 'none';

rectangle(ax1, 'Position', [0.0, 0.0, 1.0, 1.0], 'EdgeColor', [0.5, 0.5, 0.5], 'LineWidth', 1.5, 'FaceColor', [0.97, 0.97, 0.97]);

linesNbr = numel(metrics);

presentGroupCount = 0;
% Loop through each group
for i = 1:length(groups)
    group = groups{i};

    % Check if any of the group's metrics are in the metrics list
    if any(ismember(group, metrics))
        presentGroupCount = presentGroupCount + 1;
    end
end

spacerNbr = presentGroupCount + 1;

% Define margins and line properties
lineWidth = 0.02;
marginY = 0.03;
marginX = 0.03;
totalHeight = 1 - 2 * marginY;  % Total available height in the rectangle

% Calculate line spacing to ensure content fits within the rectangle
lineSpacing = (totalHeight - (linesNbr * lineWidth)) / (linesNbr + spacerNbr - 1);

% Define the function to calculate line position
linePos = @(l, s)(1 - marginY - (l - 1) * (lineWidth + lineSpacing) - s * lineSpacing);

if isscalar(subjGrp)
    posX = 0.1 + (0.5 - 0.1) / numel(subjGrp);
else
    posX = 0.1 + (0.4 - 0.1) / numel(subjGrp);
end

if numel(subjGrp) == 2
    offset = (1-marginX-posX)/(numel(subjGrp) + 1);
else
    offset = (1-marginX-posX)/numel(subjGrp);
end

line = 0;
spacer = 0;
line = line + 1;
plot(ax1, [marginX, marginX + posX - 0.03], [linePos(line, spacer), linePos(line, spacer)]-0.02, 'color', [0.5, 0.5, 0.5], 'LineWidth', 1.5);
text(ax1, marginX, linePos(line, spacer), 'Summary', 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold');
for gr = numel(subjGrp):-1:1
    text(ax1, marginX + posX + (gr-1)*offset, linePos(line, spacer), sprintf('%s (n=%d)', shortnames{gr}, numel(subjGrp{gr})), 'Color', colors{gr}, 'FontSize', 14, 'FontWeight', 'bold');
end
if numel(subjGrp) == 2
    text(ax1, marginX + posX + 2*offset, linePos(line, spacer), 'Diff', 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold');
end

% if TAR in metrics
countGrp = 1;
group = groups{countGrp};
if any(ismember(metrics, group))
    spacer = spacer + 1;

    metricList = {...
        'tar2', 250.5, inf, 'Time >250 (%)'; ...  % >250
        'tar1', 180.5, inf, 'Time >180 (%)'; ...  % >180
        'tir', 70, 180.5, 'Time In Range (%)'; ... % 70-180
        'tirp', 63, 140.5, 'Preg Range (%)'; ... % 63-140
        'titr', 70, 140.5, 'Tight Range (%)'; ... % 70-140
        'tbr1', 0, 70, 'Time <70 (%)'; ... % <70
        'tbrp1', 0, 63, 'Time <63 Preg (%)'; ... % <63
        'tbr2', 0, 54, 'Time <54 (%)'}; % <54

    for i = 1:size(metricList, 1)
        metric = metricList{i, 1};
        lowerBound = metricList{i, 2};
        upperBound = metricList{i, 3};
        metricLabel = metricList{i, 4};

        if ismember(metric, metrics)
            line = line + 1;
            text(ax1, marginX, linePos(line, spacer), metricLabel, 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
            for gr = numel(subjGrp):-1:1
                writeAverageInfo(subjGrp{gr}.getTimeIn(lowerBound, upperBound), gr, metricLabel);
            end
            if numel(subjGrp) == 2
                writeDifference(subjGrp{1}.getTimeIn(lowerBound, upperBound), subjGrp{2}.getTimeIn(lowerBound, upperBound), metricLabel);
            end
        end
    end
end

countGrp = countGrp + 1;
group = groups{countGrp};
if any(ismember(metrics, group))
    spacer = spacer + 1;

    nightMetrics = {...
        'ntar', 180.5, inf, 'Night >180 (%)'; ...
        'ntir', 70, 180.5, 'Night TIR (%)'; ...
        'ntbr', 0, 70, 'Night <70 (%)'};

    timeRange = [0, 6] * 60; % Nighttime range

    for i = 1:size(nightMetrics, 1)
        metric = nightMetrics{i, 1};
        lowerBound = nightMetrics{i, 2};
        upperBound = nightMetrics{i, 3};
        metricLabel = nightMetrics{i, 4};

        if ismember(metric, metrics)
            line = line + 1;
            text(ax1, marginX, linePos(line, spacer), metricLabel, 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
            for gr = numel(subjGrp):-1:1
                writeAverageInfo(subjGrp{gr}.getTimeIn(lowerBound, upperBound, timeRange), gr, metricLabel);
            end
            if numel(subjGrp) == 2
                writeDifference(subjGrp{1}.getTimeIn(lowerBound, upperBound, timeRange), subjGrp{2}.getTimeIn(lowerBound, upperBound, timeRange), metricLabel);
            end
        end
    end
end

countGrp = countGrp + 1;
group = groups{countGrp};
if any(ismember(metrics, group))
    spacer = spacer + 1;

    dayMetrics = {...
        'dtar', 180.5, inf, 'Day >180 (%)'; ...
        'dtir', 70, 180.5, 'Day TIR (%)'; ...
        'dtbr', 0, 70, 'Day <70 (%)'};

    timeRange = [6, 0] * 60; % Daytime range

    for i = 1:size(dayMetrics, 1)
        metric = dayMetrics{i, 1};
        lowerBound = dayMetrics{i, 2};
        upperBound = dayMetrics{i, 3};
        metricLabel = dayMetrics{i, 4};

        if ismember(metric, metrics)
            line = line + 1;
            text(ax1, marginX, linePos(line, spacer), metricLabel, 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
            for gr = numel(subjGrp):-1:1
                writeAverageInfo(subjGrp{gr}.getTimeIn(lowerBound, upperBound, timeRange), gr, metricLabel);
            end
            if numel(subjGrp) == 2
                writeDifference(subjGrp{1}.getTimeIn(lowerBound, upperBound, timeRange), subjGrp{2}.getTimeIn(lowerBound, upperBound, timeRange), metricLabel);
            end
        end
    end
end

countGrp = countGrp + 1;
group = groups{countGrp};
metricsList = {...
    'avgg', @(ii) subjGrp{ii}.getGMean(), 'Avg Glucose (mg/dl)';
    'sdg', @(ii) subjGrp{ii}.getGlucoseSD(), 'SD Glucose (mg/dl)';
    'cvg', @(ii) subjGrp{ii}.getGlucoseCV(), 'CV Glucose (%)'};

if any(ismember(metrics, group))
    spacer = spacer + 1;
    for i = 1:size(metricsList, 1)
        metric = metricsList{i, 1};
        funcHandle = metricsList{i, 2};
        metricLabel = metricsList{i, 3};

        if ismember(metric, metrics)
            line = line + 1;
            text(ax1, marginX, linePos(line, spacer), metricLabel, 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
            for gr = numel(subjGrp):-1:1
                writeAverageInfo(funcHandle(gr), gr, metricLabel);
            end
            if numel(subjGrp) == 2
                writeDifference(funcHandle(1), funcHandle(2), metricLabel);
            end
        end
    end
end


countGrp = countGrp + 1;
group = groups{countGrp};
metricsList = {...
    'avgfast', @(ii) subjGrp{ii}.getSMBGMean(), 'Avg Fasting (mg/dl)';
    'sdfast', @(ii) subjGrp{ii}.getSMBGSD(), 'SD Fasting (mg/dl)';
    'cvfast', @(ii) subjGrp{ii}.getSMBGCV(), 'CV Fasting (%)'};

if any(ismember(metrics, group))
    spacer = spacer + 1;
    for i = 1:size(metricsList, 1)
        metric = metricsList{i, 1};
        funcHandle = metricsList{i, 2};
        metricLabel = metricsList{i, 3};

        if ismember(metric, metrics)
            line = line + 1;
            text(ax1, marginX, linePos(line, spacer), metricLabel, 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
            for gr = numel(subjGrp):-1:1
                writeAverageInfo(funcHandle(gr), gr, metricLabel);
            end
            if numel(subjGrp) == 2
                writeDifference(funcHandle(1), funcHandle(2), metricLabel);
            end
        end
    end
end

countGrp = countGrp + 1;
group = groups{countGrp};
metricsList = {...
    'gmi', @(ii) subjGrp{ii}.getGMI(), 'GMI (%)';
    'lbgi', @(ii) subjGrp{ii}.getLBGI(), 'Low BG Index';
    'hbgi', @(ii) subjGrp{ii}.getHBGI(), 'High BG Index';
    'bgi', @(ii) subjGrp{ii}.getLBGI() + subjGrp{ii}.getHBGI(), 'BG Risk Index'};

if any(ismember(metrics, group))
    spacer = spacer + 1;
    for i = 1:size(metricsList, 1)
        metric = metricsList{i, 1};
        funcHandle = metricsList{i, 2};
        metricLabel = metricsList{i, 3};

        if ismember(metric, metrics)
            line = line + 1;
            text(ax1, marginX, linePos(line, spacer), metricLabel, 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
            for gr = numel(subjGrp):-1:1
                writeAverageInfo(funcHandle(gr), gr, metricLabel);
            end
            if numel(subjGrp) == 2
                writeDifference(funcHandle(1), funcHandle(2), metricLabel);
            end
        end
    end
end

countGrp = countGrp + 1;
group = groups{countGrp};
if any(ismember(metrics, group))
    spacer = spacer + 1;

    obj = subjGrp{1}.copy();
    data = obj.getSampledData(5, 'fields', {});
    duration_ = days(median([data.duration]));

    if duration_ < 1
        metricsList = {...
            'tdi',  @(ii) subjGrp{ii}.getTotalInsulin(),  'Daily Insulin (U)';
            'tdba', @(ii) subjGrp{ii}.getTotalBasal(),    'Daily Basal (U)';
            'tdbo', @(ii) subjGrp{ii}.getTotalBolus(),    'Daily Bolus (U)';
            'tdcbo', @(ii) subjGrp{ii}.getTotalCarbBolus(),    'Daily Carb Bolus (U)';
            'ntdbo', @(ii) subjGrp{ii}.getNumberOfBolus(), '#Bolus';
            'ntdbo', @(ii) subjGrp{ii}.getNumberOfCarbBolus(), '#Carb Bolus'};
    else
        metricsList = {...
            'tdi',  @(ii) subjGrp{ii}.getTotalInsulin() / duration_,  'Daily Insulin (U/day)';
            'tdba', @(ii) subjGrp{ii}.getTotalBasal() / duration_,    'Daily Basal (U/day)';
            'tdbo', @(ii) subjGrp{ii}.getTotalBolus() / duration_,    'Daily Bolus (U/day)';
            'tdcbo', @(ii) subjGrp{ii}.getTotalCarbBolus() / duration_,    'Daily Carb Bolus (U/day)';
            'ntdbo', @(ii) subjGrp{ii}.getNumberOfBolus() / duration_, '#Bolus per day';
            'ntdcbo', @(ii) subjGrp{ii}.getNumberOfCarbBolus() / duration_, '#Carb Bolus per day'};
    end

    for i = 1:size(metricsList, 1)
        metric = metricsList{i, 1};
        funcHandle = metricsList{i, 2};
        metricLabel = metricsList{i, 3};

        if ismember(metric, metrics)
            line = line + 1;
            text(ax1, marginX, linePos(line, spacer), metricLabel, 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
            for gr = numel(subjGrp):-1:1
                writeAverageInfo(funcHandle(gr), gr, metricLabel);
            end
            if numel(subjGrp) == 2
                writeDifference(funcHandle(1), funcHandle(2), metricLabel);
            end
        end
    end
end

countGrp = countGrp + 1;
group = groups{countGrp};
if any(ismember(metrics, group))
    spacer = spacer + 1;

    obj = subjGrp{1}.copy();
    data = obj.getSampledData(5, 'fields', {});
    duration_ = days(median([data.duration]));

    if duration_ < 1
    metricsList = {...
        'carb',      @(ii) subjGrp{ii}.getTotalCarbActual(),   'Carbs Consum (g)';
        'carbcount', @(ii) subjGrp{ii}.getTotalCarb(),        'Carbs Count (g)';
        'carbann',   @(ii) subjGrp{ii}.getTotalCarbAnnounced(), '#Carbs Ann';
        'treat',     @(ii) subjGrp{ii}.getTotalTreat(),       'Daily Treat (g)'};
    else
    metricsList = {...
        'carb',      @(ii) subjGrp{ii}.getTotalCarbActual()/duration_,   'Carbs Consum (g/day)';
        'carbcount', @(ii) subjGrp{ii}.getTotalCarb()/duration_,        'Carbs Count (g/day)';
        'carbann',   @(ii) subjGrp{ii}.getTotalCarbAnnounced()/duration_, '#Carbs Ann per day';
        'treat',     @(ii) subjGrp{ii}.getTotalTreat()/duration_,       'Daily Treat (g/day)'};
    end

    for i = 1:size(metricsList, 1)
        metric = metricsList{i, 1};
        funcHandle = metricsList{i, 2};
        metricLabel = metricsList{i, 3};

        if ismember(metric, metrics)
            line = line + 1;
            text(ax1, marginX, linePos(line, spacer), metricLabel, 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
            for gr = numel(subjGrp):-1:1
                writeAverageInfo(funcHandle(gr), gr, metricLabel);
            end
            if numel(subjGrp) == 2
                writeDifference(funcHandle(1), funcHandle(2), metricLabel);
            end
        end
    end
end

countGrp = countGrp + 1;

if nargout > 1
    tabMetrics = table_dat;
end
end