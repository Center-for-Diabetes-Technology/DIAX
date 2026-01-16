function [fig, ax0, ax1] = plotSummary(obj, varargin)
% deprecated check for fig object being first argument
if nargin > 1 && ~(ischar(varargin{1}) || isstring(varargin{1}))
    fprintf('Warning: The use of a figure handle as the first argument is deprecated. Use the ''fig'' or ''figure'' argument instead.\n');
    % put the figure handle in the 'fig' argument
    varargin = [{'fig', varargin{1}}, varargin(2:end)];
end 

% Check if 'fig' or 'figure' is provided in varargin
figProvided = false;
for nVar = 1:2:length(varargin)
    switch lower(varargin{nVar})
        case {'fig', 'figure'}
            fig = varargin{nVar+1};
            figProvided = true;
    end
end

% If there is only one object and its duration is greater than a day
if numel(obj) == 1 && obj.duration > days(1)
    if ~figProvided
        [fig, ax0, ax1] = obj.getDays().plotSummary();
    else
        [fig, ax0, ax1] = obj.getDays().plotSummary(fig);
    end
    return;
end

% Filter out objects with duration less than 12 hours
% obj([obj.duration] < hours(12)) = [];
if isempty(obj)
    return;
end

%TODO make this an option
outcome_type = 'mean'; % 'auto', 'mean', 'median'

% If fig is not provided, create a new figure
if ~figProvided
    figHandle = mod(sum([obj.figHandle]) + 1, 1e6);
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
end

clf(fig);
ax0 = subplot('Position', [0.05, 0.1, 0.65, 0.85]);
ax0.Tag = 'plot';

cla(ax0);
hold(ax0, 'on');
set(ax0, 'FontWeight', 'bold', 'LineWidth', 2.0, 'FontSize', 14);

blue = [0, 0.4470, 0.7410];
red = [0.8500, 0.3250, 0.0980];
darkRed = [0.6350, 0.0780, 0.1840];
purple = [0.4940, 0.1840, 0.5560];

patientNames = unique(cellfun(@(c)(c{1}), cellfun(@(c)strsplit(c, '#'), {obj.name}, 'UniformOutput', false), 'UniformOutput', false));
if contains(obj(1).name, '#') && length(patientNames) == 1
    stepTime_ = 5;
    duration_ = days(1);
    startTime_ = 0;
else
    stepTime_ = 15;
    data = obj.getSampledData(stepTime_, 'fields', {});
    duration_ = median([data.duration]);
    if duration_ < hours(12)
        duration_ = hours(round(hours(duration_))); % duration is multiple of hours
    else
        duration_ = days(round(days(duration_))); % duration is multiple of days
    end
    startTime_ = mode([data.startTime]);
end
data = obj.getSampledData(stepTime_, 'starttime', startTime_, 'duration', duration_);

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

idxValid = ~isnan(cgm.mean);

patch(ax0, 'XData', [t(idxValid); flipud(t(idxValid))] ...
    , 'YData', [cgm.iqr05(idxValid); flipud(cgm.iqr95(idxValid))], ...
    'EdgeColor', 'none', ...
    'FaceColor', darkRed, ...
    'FaceAlpha', .1)
patch(ax0, 'XData', [t(idxValid); flipud(t(idxValid))] ...
    , 'YData', [cgm.iqr25(idxValid); flipud(cgm.iqr75(idxValid))], ...
    'EdgeColor', 'none', ...
    'FaceColor', darkRed, ...
    'FaceAlpha', .3)
plot(ax0, t(idxValid), cgm.median(idxValid), ...
    'Color', darkRed, ...
    'LineStyle', '-', ...
    'Marker', '.', ...
    'MarkerSize', 20);

if all(isnan(cgm.mean))
    % smbg
    smbg.mean = mean([data.smbg], 2, 'omitnan');
    smbg.median = median([data.smbg], 2, 'omitnan');
    smbg.std = std([data.smbg], [], 2, 'omitnan');
    smbg.iqr05 = prctile([data.smbg], 05, 2);
    smbg.iqr25 = prctile([data.smbg], 25, 2);
    smbg.iqr75 = prctile([data.smbg], 75, 2);
    smbg.iqr95 = prctile([data.smbg], 95, 2);
    
    idxValid = ~isnan(smbg.mean);
    
    patch(ax0, 'XData', [t(idxValid); flipud(t(idxValid))] ...
        , 'YData', [smbg.iqr05(idxValid); flipud(smbg.iqr95(idxValid))], ...
        'EdgeColor', 'none', ...
        'FaceColor', darkRed, ...
        'FaceAlpha', .1)
    patch(ax0, 'XData', [t(idxValid); flipud(t(idxValid))] ...
        , 'YData', [smbg.iqr25(idxValid); flipud(smbg.iqr75(idxValid))], ...
        'EdgeColor', 'none', ...
        'FaceColor', darkRed, ...
        'FaceAlpha', .3)
    plot(ax0, t(idxValid), smbg.median(idxValid), ...
        'Color', darkRed, ...
        'LineStyle', '-', ...
        'Marker', '.', ...
        'MarkerSize', 20);
end

if duration_ > days(3)
    bigStepTime_ = round(3*stepTime_*days(duration_));
else
    bigStepTime_ = round(3*stepTime_);
end

if isfield(data, 'bolus') && ~isempty([data.bolus])
    bolusAll = [data.bolus];
    bolusNum = sum(reshape(sum(bolusAll > 0, 2), bigStepTime_/stepTime_, []), 1);
    bolusTime = (0:bigStepTime_:minutes(duration_)-bigStepTime_) + startTime_;
    for n = find(bolusNum(:)' > 0)
        fill(ax0, bolusTime(n) + [-1 1 0]*bigStepTime_/5, [300 300 293] - 5, blue, ...
            'EdgeColor', 'none', ...
            'FaceAlpha', min(0.2*bolusNum(n), 1)^1.5);
    end
end

if isfield(data, 'carb') && ~isempty([data.carb])
    carbAll = [data.carb];
    carbNum = sum(reshape(sum(carbAll > 0, 2), bigStepTime_/stepTime_, []), 1);
    carbTime = (0:bigStepTime_:minutes(duration_)-bigStepTime_) + startTime_;
    for n = find(carbNum(:)' > 0)
        fill(ax0, carbTime(n) + [-1 1 0]*bigStepTime_/5, [300 300 307] + 5, red, ...
            'EdgeColor', 'none', ...
            'FaceAlpha', min(0.2*carbNum(n), 1)^1.5);
    end
end

if ~isempty(obj(1).treat)
    treatAll = [data.treat];
    treatNum = sum(reshape(sum(treatAll > 0, 2), bigStepTime_/stepTime_, []), 1);
    treatTime = (0:bigStepTime_:minutes(duration_)-bigStepTime_) + startTime_;
    for n = find(treatNum(:)' > 0)
        fill(ax0, treatTime(n) + [-1 1 0]*bigStepTime_/5, [300 300 307] - 25, purple, ...
            'EdgeColor', 'none', ...
            'FaceAlpha', min(0.2*treatNum(n), 1)^1.5);
    end
end

if any(~cellfun(@isempty, {obj.basalInj}))
    basalInjAll = [data.basalInj];
    basalInjNum = sum(reshape(sum(basalInjAll > 0, 2), bigStepTime_/stepTime_, []), 1);
    basalInjTime = (0:bigStepTime_:minutes(duration_)-bigStepTime_) + startTime_;
    for n = find(basalInjNum(:)' > 0)
        fill(ax0, basalInjTime(n) + [-1 1 1 -1]*bigStepTime_/2, [300 300 307 307] + 25, blue, ...
            'EdgeColor', 'none', ...
            'FaceAlpha', min(0.2*basalInjNum(n), 1)^1.5);
    end
end

ylim([0, 400])
yticks(0:20:400);

xlim([t(1) - 30, t(end) + 30]);

showDates = false;
if t(end) - t(1) <= 2 * 60
    sTick = 0.5 * 60;
elseif t(end) - t(1) <= 8 * 60
    sTick = 1 * 60;
elseif t(end) - t(1) <= 24 * 60
    sTick = 2 * 60;
elseif t(end) - t(1) <= 48 * 60
    sTick = 4 * 60;
elseif t(end) - t(1) <= 7 * 24* 60
    sTick = 12 * 60;
elseif t(end) - t(1) <= 6 * 7 * 24* 60
    sTick = 24 * 60;
    % showDates = true;
elseif t(end) - t(1) <= 28 * 7 * 24* 60
    sTick = 7 * 24 * 60;
    % showDates = true;
else
    sTick = 4 * 7 * 24 * 60;
    % showDates = true;
end
st_ = 0.0;
xticks(ax0, (sTick*floor((t(1)+st_) / (sTick)):sTick:sTick*ceil((t(end)+st_) / (sTick)))-st_);
if ~showDates
    % xticklabels(ax0, [num2str(mod((sTick/60*floor((t(1)+st_) / (sTick)):sTick/60:sTick/60*ceil((t(end)+st_) / (sTick))), 24)'), repmat(':00', length(sTick / 60 * floor((t(1)+st_) / (sTick)):sTick / 60:sTick / 60 * ceil((t(end)+st_) / (sTick))), 1)]);
    if sTick < 1440
        xticklabels(ax0, [num2str((sTick/60*floor((t(1)+st_) / (sTick)):sTick/60:sTick/60*ceil((t(end)+st_) / (sTick)))'), repmat(':00', length(sTick / 60 * floor((t(1)+st_) / (sTick)):sTick / 60:sTick / 60 * ceil((t(end)+st_) / (sTick))), 1)]);
        ax0.XLabel.String = 'Time (HH:MM)';
    else
        xticklabels(ax0, ((sTick*floor((t(1)+st_) / (sTick)):sTick:sTick*ceil((t(end)+st_) / (sTick)))-st_)/1440);
        ax0.XLabel.String = 'Time (days)';
    end
else
    xticklabels(ax0, datestr(floor(mean([obj.startTimestamp] + [obj.dateTimeOffset])) + ((sTick*floor((t(1)+st_) / (sTick)):sTick:sTick*ceil((t(end)+st_) / (sTick)))-st_)/1440));
    ax0.XLabel.String = 'Time';
end

set(ax0, 'FontWeight', 'bold', 'LineWidth', 2.0, 'FontSize', 14);

ax0.YLabel.String = 'Sensor Glucose (mg/dl)';


    function xOut = xDataTransform(xIn)
        xOut = kron(xIn(2:end), [1; 1]);
        xOut(2:end+1) = xOut;
        xOut(1) = xIn(1);
    end

    function yOut = yDataTransform(yIn)
        yOut = kron(yIn(1:end - 1, :), [1; 1]);
        yOut(end+1, :) = yIn(end, :);
    end

if ~isempty(obj(1).basalRate)
    % basal rate
    yyaxis(ax0, 'right');
    
    basalRate.mean = mean([data.basalRate], 2, 'omitnan');
    basalRate.median = median([data.basalRate], 2, 'omitnan');
    basalRate.std = std([data.basalRate], [], 2, 'omitnan');
    basalRate.iqr05 = prctile([data.basalRate], 05, 2);
    basalRate.iqr25 = prctile([data.basalRate], 25, 2);
    basalRate.iqr75 = prctile([data.basalRate], 75, 2);
    basalRate.iqr95 = prctile([data.basalRate], 95, 2);
    
    idxValid = ~isnan(basalRate.mean);

    patch(ax0, 'XData', [xDataTransform(t(idxValid)); flipud(xDataTransform(t(idxValid)))] ...
        , 'YData', [yDataTransform(basalRate.iqr05(idxValid)); flipud(yDataTransform(basalRate.iqr95(idxValid)))], ...
        'EdgeColor', 'none', ...
        'FaceColor', blue, ...
        'FaceAlpha', .1);
    patch(ax0, 'XData', [xDataTransform(t(idxValid)); flipud(xDataTransform(t(idxValid)))] ...
        , 'YData', [yDataTransform(basalRate.iqr25(idxValid)); flipud(yDataTransform(basalRate.iqr75(idxValid)))], ...
        'EdgeColor', 'none', ...
        'FaceColor', blue, ...
        'FaceAlpha', .3);
    plot(ax0, xDataTransform(t(idxValid)), yDataTransform(basalRate.median(idxValid)), ...
        'Color', blue, ...
        'LineStyle', '-', ...
        'LineWidth', 2.0);
    
    ax0.YAxis(2).Color = [0, 0, 0];
    ax0.YLabel.String = 'Insulin Rate (U/h)';
    ax0.YLim = [0, 20];
    ax0.YTick = (0:1:20);
end
if length(patientNames) == 1
    title(ax0, sprintf('Summary data for %s from %s to %s (%4.2f days)', patientNames{1}, min([obj.startDate]), max([obj.endDate]), days(sum([duration_]))), 'FontSize', 16, 'Interpreter', 'none');
else
    title(ax0, sprintf('Summary data for %d participants %4.2f days', numel({obj.name}), days(duration_)), 'FontSize', 16, 'Interpreter', 'none');
end

ax1 = subplot('Position', [0.75, 0.10, 0.23, 0.85]);
ax1.Tag = 'summary';
% add 'ax' to varargin
if iscell(varargin)
    varargin = [varargin, {'ax', ax1}];
else
    varargin = [{'ax', ax1}];
end
varargin = [{'names', {'Subject'}}, varargin];  % add default name, this will get overwritten if 'names' is provided later in varargin

ax1 = Subject.compareMetrics({obj}, varargin{:});

end
