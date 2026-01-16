function fig = plotOutcomes(subjGrp, varargin)
if ~iscell(subjGrp)
    subjGrp = {subjGrp};
end

names = cellfun(@(c)(strcat('subj', num2str(c))), num2cell(1:numel(subjGrp)), 'UniformOutput', false);
shortnames = {};
outcomes = {};
fieldsDefault = {...
    'GMI', 'TBR1', 'TBR2', 'TAR1', 'TAR2', 'TIR', 'Smbg', 'SmbgSD', 'SmbgCV', ...
    'BasalBolusRatio', 'Basal','Bolus', 'BasalDaily', 'BolusDaily', 'Insulin', ...
    'TreatHypo2', 'TreatHypo1', 'CGMHypo2', 'CGMHypo1', 'SmbgHypo2', 'SmbgHypo1', ...
    'LBGI', 'HBGI', 'Carbs', 'Semaglutide'};
fieldsNamesDefault = {...
    'Glucose management index (%)', ...
    'Glucose < 70 mg/dL (%)',...
    'Glucose < 54 mg/dL (%)',...
    'Glucose > 180 mg/dL (%)',...
    'Glucose > 250 mg/dL (%)',...
    'Glucose in range (%)', ...
    'Mean fasting (mg/dL)', ...
    'SD fasting (mg/dL)', ...
    'CV Fasting (%)', ...
    'Basal over Bolus Ratio', ...
    'Basal Insulin (U/day)', ...
    'Bolus Insulin (U/day)', ...
    'Basal Insulin (U/day)', ...
    'Bolus Insulin (U/day)', ...
    'Insulin (U/day)', ...
    'Fasting < 54 mg/dL (#/patient/year)', ...
    'Fasting < 70 mg/dL (#/patient/year)', ...
    'Fasting < 54 mg/dL (#/patient/year)', ...
    'Fasting < 70 mg/dL (#/patient/year)', ...
    'Fasting < 54 mg/dL (#/patient/year)', ...
    'Fasting < 70 mg/dL (#/patient/year)', ...
    'Low Blood Glucose Index', ...
    'High Blood Glucose Index', ...
    'Carb Amount (g)' ...
    'Semaglutide (mg)'
    };
fields = {'GMI', 'Smbg', 'SmbgCV', 'TIR', 'Insulin', 'SmbgHypo2', 'SmbgHypo1', 'TBR1'};
fieldsNames = {};
titleString = '';
perctMin = 0.8;
wMax = inf;
freqInDays = 7;
wStep = 2;
graphType = 'iqr'; %'sd';% 'se100'; %
excludeIncompleteSubjects = false;
for nVar = 1:2:length(varargin)
    switch lower(varargin{nVar})
        case {'name', 'names', 'legend', 'arms'}
            names = varargin{nVar+1};
        case {'shortname', 'shortnames', 'shortlegend'}
            shortnames = varargin{nVar+1};
        case 'fields'
            fields = varargin{nVar+1};
        case {'fieldnames', 'fieldsnames'}
            fieldsNames = varargin{nVar+1};
        case 'title'
            titleString = varargin{nVar+1};
        case {'outcomes', 'outcome', 'out'}
            outcomes = varargin{nVar+1};
        case {'nmin', 'percentavailibledata', 'percmin'}
            perctMin = varargin{nVar+1};
        case {'graphtype', 'type'}
            graphType = varargin{nVar+1};
        case {'excludeincompletesubjects', 'excludeincomplete', 'incomplete'}
            excludeIncompleteSubjects = varargin{nVar+1};
        case {'wmax', 'timemax'}
            wMax = varargin{nVar+1};
        case {'frequency', 'freqindays', 'freq'}
            freqInDays = varargin{nVar+1};
        case {'wstep', 'step'}
            wStep = varargin{nVar+1};
    end
end
if ~iscell(names)
    names = {names};
end
if isempty(shortnames)
    shortnames = names;
end
if isempty(fieldsNames)
    for kk = length(fields):-1:1
        if any(strcmp(fieldsDefault, fields{kk}))
            fieldsNames{kk} = fieldsNamesDefault{strcmp(fieldsDefault, fields{kk})};
        else
            fieldsNames{kk} = fields{kk};
        end
    end
end

if isscalar(string(graphType))
    graphType = repmat(string(graphType), 1, length(fieldsNames));
end

subjGrbAll = [subjGrp{:}];
figHandle = mod(nansum([subjGrbAll.figHandle]) + sum(double([shortnames{:}])) + 2, 9973);
if ishandle(figHandle)
    fig = figure(figHandle);
else
    fig = figure(figHandle);
    set(fig, 'name', 'Subject::plotOutcomes', ...
        'numbertitle', 'off', ...
        'units', 'normalized', ...
        'outerposition', [0, 0, 1, 1], ...
        'defaultAxesColorOrder', [[1, 0, 0]; [0, 0, 1]]);
end

clf(fig);

offsetLines = 0.005*days(subjGrp{1}(1).duration);
colors = {...
    [0.8500, 0.3250, 0.0980], ...
    [0.4660, 0.6740, 0.1880], ...
    [0.9290, 0.6940, 0.1250], ...
    [0.4940, 0.1840, 0.5560], ...
    [0, 0.4470, 0.7410], ...
    [0.3010, 0.7450, 0.9330], ...
    [0.6350, 0.0780, 0.1840]};
markers = {'s', 'd', 'd', 'd', 'd', 'd', 'd'};

if isempty(outcomes)
    outcomes = Subject.computeOutcomes(subjGrp, varargin{:});
elseif isa(outcomes,'function_handle')
    outcomes = outcomes(subjGrp, varargin{:});
end

for gr = 1:length(names)
    fn = fieldnames(outcomes{gr});
    fn(strcmp(fn, 'time')) = [];
    names(gr) = strcat(names(gr), sprintf(' (n=%d)', size(outcomes{gr}.(fn{1}), 2)));
end

if numel(fields) > 3
    subplot_y_n = 2;
else
    subplot_y_n = 1;
end
subplot_x_n = ceil(length(fields)/subplot_y_n);
subplot_x_offset = 0.02;
subplot_x_gap = 0.025;
subplot_x_len = (1 - subplot_x_offset)/subplot_x_n - 2*subplot_x_gap;
subplot_y_offset = 0.04;
subplot_y_gap = 0.04;
subplot_y_len = (1 - subplot_y_offset)/subplot_y_n - 2*subplot_y_gap;

x_lim_min = freqInDays;
x_lim_max = inf;
for gr = numel(outcomes):-1:1
    size_ = numel(subjGrp{gr});
    for k = 1:length(fields)
        ax = subplot('Position', [...
            subplot_x_offset + (mod(k - 1, subplot_x_n)+1)*(subplot_x_len + 2*subplot_x_gap) - subplot_x_len - subplot_x_gap, ...
            subplot_y_offset + (subplot_y_n - ceil(k/subplot_x_n) + 1)*(subplot_y_len + 2*subplot_y_gap) - subplot_y_len - subplot_y_gap,...
            subplot_x_len,...
            subplot_y_len ...
            ]);
        hold(ax, 'on');
        ax.Tag = fields{k};
        if ~isfield(outcomes{gr}, fields{k})
            warning('[plotOutcomes] the outcome %s does not exist!', fields{k});
        else
            if strcmpi(graphType{k}, 'cv')
                outcomes{gr}.(fields{k})(outcomes{gr}.(fields{k}) == 0) = NaN;
            end
            if excludeIncompleteSubjects
                outcomes{gr}.(fields{k})(:, any(isnan(outcomes{gr}.(fields{k})))) = NaN;
            end
            idxValidWeek = mean(~isnan(outcomes{gr}.(fields{k})), 2) > perctMin;
            time_ = outcomes{gr}.time(idxValidWeek);
            if all(~idxValidWeek)
                continue;
            end
            switch fields{k}
                case {'SmbgHypo1', 'SmbgHypo2', 'TreatHypo1', 'TreatHypo2'}
                    val_ = cumsum(outcomes{gr}.(fields{k})(idxValidWeek, :)) * 365.25 / outcomes{gr}.time(end);
                case {'CGMHypo1', 'CGMHypo2'}
                    val_ = cumsum(outcomes{gr}.(fields{k})(idxValidWeek, :));
                otherwise
                    val_ = outcomes{gr}.(fields{k})(idxValidWeek, :);
            end
            if strcmpi(graphType{k}, 'iqr')
                PLOT(gr) = errorbar(ax, time_-(gr-1)*offsetLines, median(val_, 2, 'omitnan'), ...
                    prctile(val_, 25, 2) - median(val_, 2, 'omitnan'), prctile(val_, 75, 2) - median(val_, 2, 'omitnan'), ...
                    'LineStyle', '-', 'Color', colors{gr}, 'LineWidth', 2.5, 'Marker', markers{gr}, 'MarkerFaceColor', colors{gr}, 'MarkerSize', 3);
            elseif strcmpi(graphType{k}, 'iqr_5')
               PLOT(gr) = errorbar(ax, time_-(gr-1)*offsetLines, median(val_, 2, 'omitnan'), ...
                    prctile(val_, 5, 2) - median(val_, 2, 'omitnan'), prctile(val_, 95, 2) - median(val_, 2, 'omitnan'), ...
                    'LineStyle', '-', 'Color', colors{gr}, 'LineWidth', 2.5, 'Marker', markers{gr}, 'MarkerFaceColor', colors{gr}, 'MarkerSize', 3);
            elseif strcmpi(graphType{k}, 'sd')
                PLOT(gr) = errorbar(ax, time_-(gr-1)*offsetLines, mean(val_, 2, 'omitnan'), ...
                    std(val_, [], 2, 'omitnan'), ...
                    'LineStyle', '-', 'Color', colors{gr}, 'LineWidth', 2.5, 'Marker', markers{gr}, 'MarkerFaceColor', colors{gr}, 'MarkerSize', 3);
            elseif strcmpi(graphType{k}, 'cv')
                PLOT(gr) = errorbar(ax, time_-(gr-1)*offsetLines, geomean(val_, 2, 'omitnan'), ...
                    std(val_, [], 2, 'omitnan')./mean(val_, 2, 'omitnan'), ...
                    'LineStyle', '-', 'Color', colors{gr}, 'LineWidth', 2.5, 'Marker', markers{gr}, 'MarkerFaceColor', colors{gr}, 'MarkerSize', 3);
            elseif strcmpi(graphType{k}, 'se')
                PLOT(gr) = errorbar(ax, time_-(gr-1)*offsetLines, mean(val_, 2, 'omitnan'), ...
                    std(val_, [], 2, 'omitnan')/sqrt(size_), ...
                    'LineStyle', '-', 'Color', colors{gr}, 'LineWidth', 2.5, 'Marker', markers{gr}, 'MarkerFaceColor', colors{gr}, 'MarkerSize', 3);
            elseif strcmpi(graphType{k}, 'se100')
                PLOT(gr) = errorbar(ax, time_-(gr-1)*offsetLines, mean(val_, 2, 'omitnan'), ...
                    std(val_, [], 2, 'omitnan')/sqrt(100), ...
                    'LineStyle', '-', 'Color', colors{gr}, 'LineWidth', 2.5, 'Marker', markers{gr}, 'MarkerFaceColor', colors{gr}, 'MarkerSize', 3);
            else
                PLOT(gr) = plot(ax, time_-(gr-1)*offsetLines, mean(val_, 2, 'omitnan'), ...
                    'LineStyle', '-', 'Color', colors{gr}, 'LineWidth', 2.5, 'Marker', markers{gr}, 'MarkerFaceColor', colors{gr}, 'MarkerSize', 3);
            end
            if isinf(wMax)
                x_lim_max = min(x_lim_max, time_(end));
            end
            if gr == 1
                set(ax, 'FontWeight', 'bold', 'LineWidth', 1.5, 'FontSize', 16);
                if x_lim_max/7 > 5
                    labels_ = time_/7;
                    labels_(labels_ ~= floor(labels_)) = [];
                    xticks(labels_(wStep:wStep:end)*7);
                    xticklabels(labels_(wStep:wStep:end));
                    xlabel(ax, 'Weeks')
                    xlim(ax, 7*[x_lim_min/7 - 0.5, x_lim_max/7 + 0.5]);
                else
                    xticks(time_);
                    xticklabels(time_);
                    xlim(ax, freqInDays*[floor(x_lim_min/freqInDays) - 0.5, ceil(x_lim_max)/freqInDays + 0.5]);
                    xlabel(ax, 'Days')
                end
                ax.YGrid = 'on';
                ax.XGrid = 'on';
                ylabel(ax, fieldsNames{k});
                if k == 1
                    lgd = legend(PLOT, strrep(names, '_', ' '));
                    lgd.Box = 'off';
                    lgd.FontSize = 16;
                    lgd.Location = 'best';
                end
                % if any(contains(fields{k}, {'Basal', 'Bolus', 'Insulin', 'TBR'}))
                if any(contains(fields{k}, {'TBR'}))
                    ax.YLim(1) = 0;
                end
            end
        end
    end
end
end
