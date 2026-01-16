classdef DIAX < matlab.mixin.Copyable
    % DIAX — DIAbetes eXchange
    %   Unified, interoperable container for diabetes-related time series and metadata.
    %
    % Data Model:
    %   - Each time-series property (e.g., cgm, bg, bolus, carbs, basalRate, etc.)
    %     is a MATLAB timetable with columns: time (datetime), value (numeric).
    %   - timeSeriesFields enumerates all supported streams.
    %   - carbsCategoryMap and carbsTypeMap provide canonical mappings for meal/treatment annotations.
    %
    % Core Features:
    %   - Time range and segmentation:
    %       startDate/endDate, duration, daysCount; getDay/getDays, getWeek/getWeeks, getChunks; clip, shiftTime, removeBetween.
    %   - Aggregation and export:
    %       combine/merge subjects; toCSV/toExcel; save/savefig.
    %   - I/O helpers:
    %       jsonToStruct/structToJson; fromJSON/toJSON for JSON round-trip.
    %   - Visualization:
    %       plot, plotSummary, plotAGP; plotOutcomes/plotCompare utilities (static).
    %   - Metrics and analytics:
    %       getTimeIn (TIR/TBR/TAR), getGMI/getGMean, getGlucoseSD/CV, getHBGI/getLBGI/getRiskBG, getGRI
    %       insulin/carbohydrate summaries (getTotal*/getDaily*), event counts, basal characterization (getGBasal, getDailyBasal/getDailyPumpBasal),
    %       target/ratio/sensitivity profiles (getDailyCarbRatio, getDailyInsulinSensitivity).
    %
    % Typical Workflow:
    %   1) Construct: subj = DIAX('name','P001') or DIAX(jsonFile,'name','P001')
    %   2) Populate streams: subj.cgm = timetable(time, value); subj.bolus = timetable(time, value); subj.carbs = timetable(time, value); ...
    %   3) Segment/inspect: days = subj.getDays(); week = subj.getWeek(1);
    %   4) Analyze: tir = subj.getTimeIn(70,180); gmi = subj.getGMI(); cv = subj.getGlucoseCV();
    %   5) Visualize/export: subj.plot(); subj.savefig('out/'); subj.toCSV('out/')
    %

    % constant properties
    properties (SetAccess = public, GetAccess = public, Hidden)
        name = 'diax'
        age
        t1dDuration
        BW
        BH
        hbA1c
        gender
        TDI
        TBI
    end

    % timetables properties
    properties (SetAccess = public, GetAccess = public)
        bg
        smbg
        cgm
        basalRate
        basalInj
        basalInjType
        bolus
        bolusType
        bolusAuto
        bolusManual
        bolusCorr
        bolusCarb
        carbs
        carbsActual
        carbsCategory % e.g. 0: Small, 1: Medium, 2: Large
        carbsType % e.g., 0: Breakfast, 1: Lunch, 2: Dinner, 3: Snack
        treat
        exercise
        glp1Inj
        steps
        heartRate
        penBasal % default basal from pen injections
        pumpBasal % default basal from pump
        fixedDose % default fixed dose insulin injections
        carbRatio % default carbohydrate ratio
        insulinSensitivity % default insulin sensitivity factor
        glucoseTarget % default glucose target
    end

    % private properties used to simplify processing
    properties (SetAccess = private, GetAccess = public, Hidden)
        carbsCategoryMap = struct('ht', 0, 'hypo', 0, 'treat', 0, ...
            'small', 1, 'lessusual', 1, 'low', 1, ...
            'medium', 2, 'usual', 2, ...
            'large', 3, 'moreusual', 3, 'high', 3);
        carbsTypeMap = struct('breakfast', 1, 'lunch', 2, 'dinner', 3, 'snack', 4);
        timeSeriesFields = {'bg', 'smbg', 'cgm', 'basalRate', 'basalInj', 'basalInjType', ...
            'bolus', 'bolusType', 'bolusAuto', 'bolusManual', 'bolusCorr', 'bolusCarb', ...
            'carbs', 'carbsActual', 'carbsCategory', 'carbsType', ...
            'treat', 'exercise', 'glp1Inj', 'steps', 'heartRate', ...
            'penBasal', 'pumpBasal', 'fixedDose', 'carbRatio', 'insulinSensitivity', 'glucoseTarget'};
        useBG = false;
    end

    % define handy dependent properties
    properties (Dependent, Hidden)
        BMI
        TDIPerBW
        figHandle
    end

    properties (Dependent)
        id
        isEmpty
        startDate
        endDate
        startTimeInMinutes
        endTimeInMinutes
        duration
        durationCGM
        daysCount
    end

    methods (Access = public)
        out = getDay(obj, dayNo, offset, times, firstDay);
        [fig, ax0, ax1] = plot(obj, varargin);
        ax0 = plotData(obj, ax0);
        [fig, ax0, ax1] = plotSummary(obj, varargin);
        [fig, axes] = plotAGP(obj, axes);
    end

    methods (Access = public)
        function obj = DIAX(varargin)
            % DIAX Construct an instance of this class
            % check if filename is given
            if mod(length(varargin), 2) ~= 0 && isfolder(varargin{1})
                listings = dir([varargin{1} '/*.json']);
                for i = 1:length(listings)
                    obj = [obj, DIAX([listings(i).folder filesep listings(i).name], varargin{2:end})];
                end
                return;
            end
            jsonData = struct();
            if mod(length(varargin), 2) ~= 0
                % assume first argument is json filename
                jsonData = DIAX.jsonToStruct(varargin{1});
                % remove first argument from varargin
                varargin = varargin(2:end);
            end
            for nVar = 1:2:length(varargin)
                switch lower(varargin{nVar})
                    case 'name'
                        obj.name = char(varargin{nVar+1});
                    case {'unique_id', 'id', 'uid', 'subj_id', 'subject_id'}
                        obj.id = varargin{nVar+1};
                end
            end

            if ~isempty(jsonData)
                obj = obj.fromJSON(jsonData);
            end
        end

        function obj = fromJSON(obj, jsonData)
            if isfield(jsonData, 'unique_id')
                obj.name = jsonData.unique_id;
            elseif isfield(jsonData, 'uid')
                obj.name = jsonData.uid;
            elseif isfield(jsonData, 'subject_id')
                obj.name = jsonData.subject_id;
            end
            if ~ischar(obj.name)
                obj.name = char(string(obj.name));
            end

            % build map for what fields in json map to what in class
            % Build a robust mapping from snake_case (PEP8) to lowerCamelCase (MATLAB)
            fieldMap = containers.Map('KeyType','char','ValueType','char');

            % Base mapping: auto-generate snake_case keys for all known timeSeriesFields
            for i = 1:numel(obj.timeSeriesFields)
                f = obj.timeSeriesFields{i};
                snake = lower(regexprep(f, '([a-z0-9])([A-Z])', '$1_$2'));
                fieldMap(snake) = f;  % snake_case -> class field
            end

            % read each field in the map if it exists in the json
            for k = keys(fieldMap)
                jsonField = k{1};
                classField = fieldMap(jsonField);
                if isfield(jsonData, jsonField) && ~isempty(jsonData.(jsonField).time)
                    % time is EITHER: Y-m-d H:M:S, OR Y-m-d H:M:S Z
                    % if Y-m-d H:M:S Z, then: data_time = datetime(ss.(jsonField).time, 'InputFormat','yyyy-MM-dd HH:mm:ss ''UTC''Z', 'TimeZone','UTC');
                    % if Y-m-d H:M:S, then: data_time = data.time (datenum can convert directly)
                    try
                        time = datetime(jsonData.(jsonField).time, 'InputFormat','yyyy-MM-dd HH:mm:ss ''UTC''Z', 'TimeZone','UTC');
                    catch
                        time = datetime(jsonData.(jsonField).time);
                    end

                    value = jsonData.(jsonField).value;
                    obj.(classField) = timetable(time, value);
                    obj.(classField) = unique(obj.(classField), 'rows');
                end
            end

            % fields that >0 only
            field_pos = {'bolus', 'carbs'};
            for f = 1:length(field_pos)
                fld = field_pos{f};
                if isprop(obj, fld) && ~isempty(obj.(fld))
                    idxToRemove = obj.(fld).value <= 0;
                    obj.(fld)(idxToRemove, :) = [];
                end
            end

            % hypotreatment is special case of carbsCategory
            % if carbsCategory is 'HT', then the carbs consumed at that time should be moved to hypotreatment
            % if no carbs at that time, then add a 15g carb hypotreatment entry
            if isprop(obj, 'carbsCategory') && ~isempty(obj.carbsCategory)
                % Use carbsCategoryMap to detect hypo-treatment categories and move carbs to treat
                map = obj.carbsCategoryMap;
                hypoVals = unique([map.ht, map.hypo, map.treat]); % numeric codes considered as hypotreatment

                % Normalize category values to numeric using the map
                catVals = obj.carbsCategory.value;
                n = height(obj.carbsCategory);
                catNum = NaN(n, 1);
                for i = 1:n
                    v = catVals(i);
                    if iscell(v), v = v{1}; end
                    if isnumeric(v)
                        catNum(i) = v;
                    else
                        key = lower(strtrim(char(string(v))));
                        if isfield(map, key)
                            catNum(i) = map.(key);
                        else
                            numv = str2double(key);
                            if ~isnan(numv), catNum(i) = numv; end
                        end
                    end
                end

                % Times where category is hypotreatment
                ht_mask = ismember(catNum, hypoVals);
                ht_times = obj.carbsCategory.time(ht_mask);

                if ~isempty(ht_times)
                    if isempty(obj.treat), obj.treat = timetable(datetime.empty, [], 'VariableNames', {'value'}); end
                    for k = 1:numel(ht_times)
                        ht_time = ht_times(k);
                        % find carbs within 1 minute of the HT time
                        idx = [];
                        if ~isempty(obj.carbs)
                            idx = find(abs(minutes(obj.carbs.time - ht_time)) < 1);
                        end
                        if ~isempty(idx)
                            % move these carbs to hypotreatment
                            obj.treat = [obj.treat; obj.carbs(idx, :)];
                            obj.carbs(idx, :) = [];
                        else
                            % add a 15g carb hypotreatment entry
                            obj.treat = [obj.treat; timetable(ht_time, 15, 'VariableNames', {'value'})];
                        end
                    end
                end
            end
        end

        function jsonData = toJSON(obj, filename)
            % Convert DIAX object to JSON-compatible structure
            if numel(obj) > 1
                if exist('filename', 'var')
                    foldername = fileparts(filename);
                else
                    foldername = './';
                end
                jsonDatas = arrayfun(@(e)(e.toJSON([foldername, filesep, e.name '.json'])), obj, 'UniformOutput', false);
                jsonData = [jsonDatas(:)];
                return;
            end

            % Initialize output structure
            jsonData = struct();

            % Add subject identifier
            jsonData.unique_id = obj.name;

            % Build reverse mapping from class fields to snake_case JSON fields
            fieldMap = containers.Map('KeyType','char','ValueType','char');
            for i = 1:numel(obj.timeSeriesFields)
                f = obj.timeSeriesFields{i};
                snake = lower(regexprep(f, '([a-z0-9])([A-Z])', '$1_$2'));
                fieldMap(f) = snake;  % class field -> snake_case
            end

            % Export each time series field
            for i = 1:numel(obj.timeSeriesFields)
                classField = obj.timeSeriesFields{i};
                jsonField = fieldMap(classField);

                if ~isempty(obj.(classField)) && istimetable(obj.(classField))
                    tt = obj.(classField);

                    % Convert datetime to string with timezone
                    timeStrings = cellstr(datestr(tt.time, 'yyyy-mm-dd HH:MM:SS'));

                    % Add timezone if available
                    if ~isempty(tt.time.TimeZone)
                        tz = tt.time.TimeZone;
                        timeStrings = cellfun(@(s) [s ' ' tz], timeStrings, 'UniformOutput', false);
                    else
                        % Default to UTC if no timezone
                        timeStrings = cellfun(@(s) [s ' UTC'], timeStrings, 'UniformOutput', false);
                    end

                    % Create field structure
                    jsonData.(jsonField) = struct();
                    jsonData.(jsonField).time = timeStrings;
                    jsonData.(jsonField).value = tt.value;
                end
            end

            % Add metadata for non-empty fields
            if isfield(jsonData, 'cgm') || isfield(jsonData, 'bolus') || ...
                    isfield(jsonData, 'basal_rate') || isfield(jsonData, 'carbs')

                jsonData.metadata = struct();
                jsonData.metadata.time = struct('unit', 'Y-m-d H:M:S Z', ...
                    'description', 'Timestamps for each data point, in local time with timezone info');

                if isfield(jsonData, 'cgm')
                    jsonData.metadata.cgm = struct('unit', 'mg/dL', ...
                        'description', 'Continuous Glucose Monitoring (CGM) data');
                end

                if isfield(jsonData, 'smbg')
                    jsonData.metadata.smbg = struct('unit', 'mg/dL', ...
                        'description', 'Self-Monitored Blood Glucose (SMBG) data');
                end

                if isfield(jsonData, 'bolus')
                    jsonData.metadata.bolus = struct('unit', 'U', ...
                        'description', 'Insulin bolus data, meal and correction, in units');
                end

                if isfield(jsonData, 'basal_rate')
                    jsonData.metadata.basal_rate = struct('unit', 'U/h', ...
                        'description', 'Basal insulin delivery rate');
                end

                if isfield(jsonData, 'basal_inj')
                    jsonData.metadata.basal_inj = struct('unit', 'U', ...
                        'description', 'Basal insulin injection doses');
                end

                if isfield(jsonData, 'carbs')
                    jsonData.metadata.carbs = struct('unit', 'g', ...
                        'description', 'User announced carbohydrate intake');
                end

                if isfield(jsonData, 'treat')
                    jsonData.metadata.treat = struct('unit', 'g', ...
                        'description', 'Carbohydrates consumed for hypoglycemia treatment');
                end

                if isfield(jsonData, 'exercise')
                    jsonData.metadata.exercise = struct('unit', 'minutes', ...
                        'description', 'Exercise duration');
                end
            end

            if nargout == 0 || exist('filename', 'var') == 0
                % save file instead of returning structure
                if ~exist('filename', 'var')
                    filename = sprintf('%s.json', obj.name);
                end
                DIAX.structToJson(jsonData, filename);
            end
        end

        function subj = get(obj, ids)
            if numel(obj) > 1
                if isnumeric(ids)
                    subj = obj([obj.id] == ids);
                else
                    subj = obj(strcmp(ids, {obj.name}));
                end
            else
                subj = obj;
            end
        end

        function shiftTime(obj, val)
            if numel(obj) > 1
                arrayfun(@(e)(e.shiftTime(val)), obj);
                return;
            end
            for fn = obj.fields
                if isempty(obj.(fn{1}))
                    continue;
                end
                ts = obj.(fn{1});
                % accept either numeric (days) or duration for val
                if isnumeric(val)
                    delta = days(val);
                elseif isduration(val)
                    delta = val;
                else
                    error('shiftTime: val must be numeric days or a duration');
                end
                ts.time = ts.time + delta;
                obj.(fn{1}) = ts;
            end
            if ~isempty(obj.raw)
                obj.raw = [];
            end
        end

        function removeBetween(obj, startTimestamp, endTimestamp)
            if numel(obj) > 1
                arrayfun(@(e)(e.removeBetween(startTimestamp, endTimestamp)), obj);
                return;
            end

            % start_t = obj.start
            for fn = obj.fields
                if isempty(obj.(fn{1}))
                    continue;
                end
                ts = obj.(fn{1});
                st = startTimestamp;
                et = endTimestamp;
                mask = ts.time < st | ts.time > et;
                ts = ts(mask, :);
                obj.(fn{1}) = ts;
            end
        end

        function obj_out = clip(obj, pre, post)
            if numel(obj) > 1
                if isscalar(pre)
                    pre = repmat(pre, [1, numel(obj)]);
                end
                if nargin == 3
                    if isscalar(post)
                        post = repmat(post, [1, numel(obj)]);
                    end
                end

                for k = numel(obj):-1:1
                    if nargin == 3
                        obj_out(k) = obj(k).clip(pre(k), post(k));
                    else
                        obj_out(k) = obj(k).clip(pre(k));
                    end
                end
                return;
            end
            obj_out = obj.copy();
            obj_out.startDate = obj_out.startDate + pre;
            if nargin == 3
                obj_out.endDate = obj_out.endDate - post;
            end
        end

        function savefig(obj, fullpath, varargin)
            individual_ = true;
            summary_ = true;
            override_ = true;
            if isprop(obj, 'id')
                ids_ = [obj.id];
            end
            for nVar = 1:2:length(varargin)
                switch lower(varargin{nVar})
                    case {'replace', 'override'}
                        override_ = varargin{nVar+1};
                    case {'summary', 'summaryplot'}
                        summary_ = varargin{nVar+1};
                        individual_ = ~varargin{nVar+1};
                    case {'indiv', 'individual', 'single'}
                        individual_ = varargin{nVar+1};
                        summary_ = ~varargin{nVar+1};
                    case 'ids'
                        ids_ = intersect(ids_, varargin{nVar+1});
                end
            end
            ids_ = unique(ids_);

            fig = figure('name', 'DIAX::savefig', ...
                'Visible', 'off', ...
                'numbertitle', 'off', ...
                'units', 'normalized', ...
                'outerposition', [0, 0, 1, 1], ...
                'defaultAxesColorOrder', [[1, 0, 0]; [0, 0, 1]]);

            if numel(obj) > 1
                [path, filename] = obj.ensureFolder(fullpath, 'summary');
            else
                [path, filename] = obj.ensureFolder(fullpath, obj.name);
            end

            if ~override_ && exist([path, filename, '.png'], 'file') == 2
                return;
            end

            if numel(obj) == 1 || summary_
                fig = obj.plot('fig', fig);
            end

            print(fig, [path, filename], '-dpng');
            saveas(fig, [path, filename], 'fig');

            close(fig);

            if numel(obj) > 1 && individual_
                for id = ids_(:)'
                    obj([obj.id] == id).savefig(fullpath, varargin{:}, 'single', true);
                end
            end
        end

        function save(obj, fullpath, varargin)
            summary_ = true;
            individual_ = true;
            for nVar = 1:2:length(varargin)
                switch lower(varargin{nVar})
                    case {'summary', 'summaryplot'}
                        summary_ = varargin{nVar+1};
                        individual_ = ~varargin{nVar+1};
                    case {'indiv', 'individual', 'single'}
                        individual_ = varargin{nVar+1};
                        summary_ = ~varargin{nVar+1};
                end
            end
            if numel(obj) > 1
                if individual_
                    arrayfun(@(e)(e.save([fullpath, filesep])), obj);
                end
                [path, filename] = obj.ensureFolder([fullpath, filesep], [class(obj), '_' num2str(numel(obj))]);
                if summary_
                    DIAXs = obj;
                    save([path, filename, '.mat'], 'DIAXs', '-v7.3');
                end
                return;
            end
            [path, filename] = obj.ensureFolder(fullpath, obj.name);
            filename = replace(filename, '#', '_');
            DIAX = obj;
            if ~isempty(obj.model)
                ssmodel = obj.model;
                save([path, filename, '.mat'], 'DIAX', 'ssmodel');
            else
                save([path, filename, '.mat'], 'DIAX');
            end
        end

        function out = getChunks(obj, frequencyInDays, durationInDays)
            if length(frequencyInDays) > 1
                array_cell_ = {};
                for k = length(frequencyInDays):-1:1
                    array_cell_{k} = (sum(frequencyInDays(1:(k-1)))+1:sum(frequencyInDays(1:k)))';
                end
            else
                if nargin < 3
                    durationInDays = frequencyInDays;
                end
                allDays = max([obj.daysCount]);
                array_ = (frequencyInDays:frequencyInDays:ceil(allDays/frequencyInDays)*frequencyInDays) + (-durationInDays+1:1:0)';
                array_(array_ <= 0) = NaN;
                array_cell_ = {};
                for k = size(array_, 2):-1:1
                    array_cell_{k} = rmmissing(array_(:, k));
                end
            end
            out_ = obj.getDay(array_cell_);
            if iscell(out_)
                out_ = [out_{:}];
                out_size_ = numel(array_cell_);
                for k = out_size_:-1:1
                    out{k} = [out_(k:out_size_:end)];
                end
            else
                out = num2cell(out_);
            end
        end

        function out = getDays(obj, offset)
            if nargin < 2
                offset = [0.0, 0.0];
            end

            allDays = obj.daysCount;
            out = obj.getDay(num2cell(1:allDays), offset);
        end

        function out = getWeek(obj, weekNo, varargin)
            if iscell(weekNo)
                out = cellfun(@(c)(obj.getWeek(c, varargin{:})), weekNo);
                return;
            end
            if weekNo > 0
                out = obj.getDay((min(weekNo)-1)*7+1:max(weekNo)*7, varargin{:});
            else
                out = obj.getDay(min(weekNo)*7:(max(weekNo)+1)*7-1, varargin{:});
            end
        end

        function out = getWeeks(obj, offset)
            if nargin < 2
                offset = [0.0, 0.0];
            end

            allDays = obj.daysCount;
            out = obj.getWeek(num2cell(1:ceil(allDays/7)), offset);
        end

        function fig = plotWeek(obj, weekNo)
            if nargin < 2
                weekNo = 1;
            end
            fig = obj.getWeek(weekNo).getDays().plot;
        end

        function subjAll = combine(obj)
            eval(sprintf('subjAll = %s();', class(obj)));
            fields_ = subjAll.fields;
            for idx = 1:length(fields_)
                if strcmp(fields_{idx}, 'carbsActual')
                    bb = 1;
                end
                subjAll.(fields_{idx}) = vertcat(obj.(fields_{idx}));
                if ~isempty(subjAll.(fields_{idx}))
                    % Remove duplicate timestamps, keeping first occurrence
                    [uniqueTime, idxUniqueTime] = unique(subjAll.(fields_{idx}).time);
                    subjAll.(fields_{idx}) = subjAll.(fields_{idx})(idxUniqueTime, :);
                end
            end

            names = unique(cellfun(@(c)(c{1}), cellfun(@(c)(strsplit(c, '#')), {obj.name}, 'UniformOutput', false), 'UniformOutput', false));
            if isscalar(names)
                subjAll.name = names{1};
            else
                subjAll.name = strjoin(names, '_');
            end
            subjAll.dateTimeOffset = min([obj.dateTimeOffset]);
            subjAll.Age = mean([obj.Age]);
            subjAll.BW = mean([obj.BW]);
            subjAll.BH = mean([obj.BH]);
            subjAll.TDI = mean([obj.TDI]);
            subjAll.TBI = mean([obj.TBI]);
            subjAll.GBasal = mean([obj.GBasal]);
            subjAll.IOB0 = mean([obj.IOB0]);
            subjAll.COB0 = mean([obj.COB0]);
        end

        function data = toExcel(obj, fullpath)
            [path, filename] = obj.ensureFolder(fullpath);
            for n = numel(obj):-1:1
                data = obj(n).toCSV();
                writetable(struct2table(data), [path, filename, '.xlsx'], 'Sheet', obj(n).name);
            end
        end

        function data = toCSV(obj, fullpath)
            data = struct('time', [], 'timeInMinutes', [], 'type', [], 'value', []);
            for idx = 1:length(obj.fields)
                ttName = obj.fields{idx};
                tt = obj.(ttName);
                if ~isempty(tt)
                    if istimetable(tt)
                        data.time = [data.time; tt.time];
                        data.type = [data.type; repmat(string(ttName), height(tt), 1)];
                        if any(strcmp('value', tt.Properties.VariableNames))
                            data.value = [data.value; tt.value];
                        else
                            % if variable not named 'value', take the first variable
                            vname = tt.Properties.VariableNames{1};
                            data.value = [data.value; tt.(vname)];
                        end
                    end
                end
            end

            [data.time, idxSorted] = sort(data.time);
            % convert to minutes offset from first timestamp
            data.timeInMinutes = minutes(data.time - data.time(1));
            data.type = data.type(idxSorted);
            data.value = data.value(idxSorted);

            if exist('fullpath', 'var') == 1
                [path, filename] = obj.ensureFolder(fullpath, obj.name);
                writetable(struct2table(data), [path, filename, '.csv']);
            end
        end

        function setUseBG(obj, val)
            if numel(obj) > 1
                arrayfun(@(e)(e.setUseBG(val)), obj);
                return;
            end
            obj.useBG = val;
        end

        function val = getHBGI(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getHBGI(interval, intervalIsDaily)), obj);
                return;
            end
            val = obj.getRiskBG(interval, intervalIsDaily);
            val(val < 0) = 0;
            if isempty(val)
                val = 0;
            else
                val = 10*mean(val.^2, 'omitnan');
            end
        end

        function val = getLBGI(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getLBGI(interval, intervalIsDaily)), obj);
                return;
            end
            val = obj.getRiskBG(interval, intervalIsDaily);
            val(val > 0) = 0;
            if isempty(val)
                val = 0;
            else
                val = 10*mean(val.^2, 'omitnan');
            end
        end

        function val = getRiskBG(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getRiskBG(interval, intervalIsDaily)), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = NaN;
            if ~isempty(obj.cgm)
                alpha = 1.084;
                beta = 5.381;
                gamma = 1.509;
                tt = obj.cgm;
                if obj.useBG && ~isempty(obj.bg)
                    tt = obj.bg;
                end
                if ~isempty(interval)
                    if intervalIsDaily
                        tod = hours(timeofday(tt.time))*60 + minutes(timeofday(tt.time)) + seconds(timeofday(tt.time))/60;
                        if interval(2) > interval(1)
                            mask = (tod >= interval(1)) & (tod < interval(2));
                        else
                            mask = (tod >= interval(1)) | (tod < interval(2));
                        end
                        vals = tt.value(mask);
                        % bin to 5 minutes across days
                        todSel = tod(mask);
                        bins = round(todSel/5)*5;
                        [~,~,ib] = unique(bins);
                        cgmUnique = accumarray(ib, vals, [], @mean);
                        val = gamma * (log(cgmUnique).^alpha - beta);
                    else
                        mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                        vals = tt.value(mask);
                        val = gamma * (log(vals).^alpha - beta);
                    end
                else
                    % retime to a 5-min grid then compute risk
                    try
                        tt5 = retime(tt, 'regular', @mean, 'TimeStep', minutes(5));
                        vals = tt5.value;
                    catch
                        vals = tt.value;
                    end
                    val = gamma * (log(vals).^alpha - beta);
                end
            end
        end

        function val = getRLScore(obj)
            hypo_hyper_ratio = 2;

            TBR2 = obj.getTimeIn(0, 54);
            TBR1 = obj.getTimeIn(0, 70);
            TIR = obj.getTimeIn(70, 180.5);
            TAR1 = obj.getTimeIn(180.5, inf);
            TAR2 = obj.getTimeIn(250.5, inf);

            scoreNeg = ...
                + hypo_hyper_ratio*max(TBR2/1.0 - 1.0, 0.0) ...
                + hypo_hyper_ratio*max(TBR1/4.0 - 1.0, 0.0) ...
                + max(TAR1/26.0 - 1.0, 0.0) ...
                + max(TAR2/5.0 - 1.0, 0.0);
            scoreNegMax = ...
                + hypo_hyper_ratio*(1.2 / 1.0 - 1.0) ...
                + hypo_hyper_ratio*(5.0 / 4.0 - 1.0) ...
                + (45.0 / 26.0 - 1) ...
                + (10.0 / 5.0 - 1);

            scorePos = max(TIR / 70.0 - 1.0, 0.0);
            scorePosMax = (90.0 / 70.0 - 1.0);
            val = 10*(-(scoreNeg / scoreNegMax) + (scorePos / scorePosMax));
        end


        function val = getTimeIn(obj, from, to, interval, intervalIsDaily)
            if nargin < 4
                interval = [];
            end
            if nargin < 5
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getTimeIn(from, to, interval, intervalIsDaily)), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = NaN;
            if isempty(obj)
                return;
            end
            if ~isempty(obj.cgm)
                tt = obj.cgm;
                if obj.useBG && ~isempty(obj.bg)
                    tt = obj.bg;
                end
                if ~isempty(interval)
                    if intervalIsDaily
                        tod = hours(timeofday(tt.time))*60 + minutes(timeofday(tt.time)) + seconds(timeofday(tt.time))/60;
                        if interval(2) > interval(1)
                            mask = (tod >= interval(1)) & (tod < interval(2));
                        else
                            mask = (tod >= interval(1)) | (tod < interval(2));
                        end
                        vals = tt.value(mask);
                        % collapse to 5-min bins across days
                        todSel = tod(mask);
                        bins = round(todSel/5)*5;
                        [ub,~,ib] = unique(bins);
                        cgmUnique = accumarray(ib, vals, [], @mean);
                        val = mean(cgmUnique >= from & cgmUnique < to, 'omitnan') * 100;
                    else
                        mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                        vals = tt.value(mask);
                        val = mean(vals >= from & vals < to, 'omitnan') * 100;
                    end
                else
                    % retime to 5-min and compute overall proportion
                    try
                        tt5 = retime(tt, 'regular', @mean, 'TimeStep', minutes(5));
                        vals = tt5.value;
                    catch
                        vals = tt.value;
                    end
                    val = mean(vals >= from & vals < to, 'omitnan') * 100;
                end
            end
        end

        function val = getGRI(obj)
            val = 3 * obj.getTimeIn(0, 54) ...
                + 2.4 * obj.getTimeIn(54, 70) ...
                + 1.6 * obj.getTimeIn(250.5, inf) ...
                + 0.8 * obj.getTimeIn(180.5, 250);
        end

        function val = getGMI(obj, bias)
            if nargin < 2
                bias = 1.0;
            end
            val = 3.31 + 0.02392 * obj.getGMean() * bias;
        end

        function val = getGMean(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getGMean(interval, intervalIsDaily)), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = NaN;
            if isempty(obj)
                return;
            end
            if ~isempty(obj.cgm)
                tt = obj.cgm;
                if obj.useBG && ~isempty(obj.bg)
                    tt = obj.bg;
                end
                if ~isempty(interval)
                    if intervalIsDaily
                        tod = hours(timeofday(tt.time))*60 + minutes(timeofday(tt.time)) + seconds(timeofday(tt.time))/60;
                        if interval(2) > interval(1)
                            mask = (tod >= interval(1)) & (tod < interval(2));
                        else
                            mask = (tod >= interval(1)) | (tod < interval(2));
                        end
                        vals = tt.value(mask);
                        % collapse to 5-min bins across days
                        todSel = tod(mask);
                        bins = round(todSel/5)*5;
                        [~,~,ib] = unique(bins);
                        cgmUnique = accumarray(ib, vals, [], @mean);
                        val = mean(cgmUnique, 'omitnan');
                    else
                        mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                        vals = tt.value(mask);
                        val = mean(vals, 'omitnan');
                    end
                else
                    % retime to uniform 5-min grid then average
                    try
                        tt5 = retime(tt, 'regular', @mean, 'TimeStep', minutes(5));
                        vals = tt5.value;
                    catch
                        vals = tt.value;
                    end
                    val = mean(vals, 'omitnan');
                end
            end
        end

        function val = getSMBGMean(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getSMBGMean()), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = NaN;
            if isempty(obj)
                return;
            end
            if ~isempty(obj.smbg)
                if obj.useBG && ~isempty(obj.fbg)
                    tt = obj.fbg;
                else
                    tt = obj.smbg;
                end
                val = mean(tt.value);
            end
        end

        function val = getSMBGSD(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getSMBGSD()), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = NaN;
            if ~isempty(obj.smbg)
                if obj.useBG && ~isempty(obj.fbg)
                    tt = obj.fbg;
                else
                    tt = obj.smbg;
                end
                val = std(tt.value);
            end
        end

        function val = getSMBGCV(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getSMBGCV()), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = NaN;
            if ~isempty(obj.smbg)
                if obj.useBG && ~isempty(obj.fbg)
                    tt = obj.fbg;
                else
                    tt = obj.smbg;
                end
                val = 100 * std(tt.value) / mean(tt.value);
            end
        end

        function val = getSMBGFastingMean(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getSMBGFastingMean()), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = NaN;
            if ~isempty(obj.smbgFasting)
                if obj.useBG && ~isempty(obj.fbgFasting)
                    tt = obj.fbgFasting;
                else
                    tt = obj.smbgFasting;
                end
                val = mean(tt.value);
            end
        end

        function val = getSMBGFastingSD(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getSMBGFastingSD()), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = NaN;
            if ~isempty(obj.smbgFasting)
                if obj.useBG && ~isempty(obj.fbgFasting)
                    tt = obj.fbgFasting;
                else
                    tt = obj.smbgFasting;
                end
                val = std(tt.value);
            end
        end

        function val = getSMBGFastingCV(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getSMBGFastingCV()), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = NaN;
            if ~isempty(obj.smbgFasting)
                if obj.useBG && ~isempty(obj.fbgFasting)
                    tt = obj.fbgFasting;
                else
                    tt = obj.smbgFasting;
                end
                val = 100 * std(tt.value) / mean(tt.value);
            end
        end

        function val = getSMBGLess(obj, thresh)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getSMBGLess(thresh)), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = NaN;
            if ~isempty(obj.smbg)
                val = sum(obj.smbg.value < thresh);
            end
        end

        function val = getTreatsAmount(obj, amount)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getTreatsAmount(amount)), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = 0;
            if ~isempty(obj.treat)
                val = sum(obj.treat.value == amount);
            end
        end

        function val = getTreatsLess(obj, thresh)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getTreatsLess(thresh)), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = 0;
            if ~isempty(obj.treat)
                res = minutes(min(diff(obj.cgm.time)))/2;
                for k = 1:height(obj.treat)
                    treatTime = obj.treat.time(k);
                    timeDiff = abs(minutes(obj.cgm.time - treatTime));
                    cgmNear = obj.cgm.value(timeDiff < res);
                    if ~isempty(cgmNear) && cgmNear(1) <= thresh
                        val = val + 1;
                    end
                end
            end
        end

        function val = getCGMHypoLvl1(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getCGMHypoLvl1()), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = 0;
            if ~isempty(obj.cgm)
                data = obj.getSampledData(5, 'fields', {'cgm'}, 'gap', 0, 'pre', false, 'post', false);

                cgm_ = data.cgm;
                cgmLess70 = cgm_ < 70;
                cgmLess70Start = find([cgmLess70(1) == 1; diff(cgmLess70) == 1])';
                cgmLess70End = find([diff(cgmLess70) == -1; cgmLess70(end) == 1])';

                for k = 1:length(cgmLess70Start)
                    cgm_tmp_ = cgm_(cgmLess70Start(k):cgmLess70End(k));
                    cgm_tmp_(isnan(cgm_tmp_)) = [];
                    if 5*length(cgm_tmp_) >= 15
                        isCGMUnder54 = 5*sum(cgm_tmp_ < 54) >= 15;
                        if ~isCGMUnder54
                            val = val + 5*length(cgm_tmp_);
                        end
                    end
                end

                val = 0.4 * val / 60;
            end
        end

        function val = getCGMHypoLvl2(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getCGMHypoLvl2()), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = 0;
            if ~isempty(obj.cgm)
                data = obj.getSampledData(5, 'fields', {'cgm'}, 'gap', 0, 'pre', false, 'post', false);

                cgm_ = data.cgm;
                cgmLess70 = cgm_ < 70;
                cgmLess70Start = find([cgmLess70(1) == 1; diff(cgmLess70) == 1])';
                cgmLess70End = find([diff(cgmLess70) == -1; cgmLess70(end) == 1])';

                for k = 1:length(cgmLess70Start)
                    cgm_tmp_ = cgm_(cgmLess70Start(k):cgmLess70End(k));
                    cgm_tmp_(isnan(cgm_tmp_)) = [];
                    if 5*length(cgm_tmp_) >= 15
                        isCGMUnder54 = 5*sum(cgm_tmp_ < 54) >= 15;
                        if isCGMUnder54
                            val = val + 5*length(cgm_tmp_);
                        end
                    end
                end

                val = 0.27 * val / 60;
            end
        end

        function val = getGlucoseSD(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getGlucoseSD(interval, intervalIsDaily)), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = NaN;
            if ~isempty(obj.cgm)
                tt = obj.cgm;
                if obj.useBG && ~isempty(obj.bg)
                    tt = obj.bg;
                end
                if ~isempty(interval)
                    if intervalIsDaily
                        tod = minutes(timeofday(tt.time));
                        if interval(2) > interval(1)
                            mask = (tod >= interval(1)) & (tod < interval(2));
                        else
                            mask = (tod >= interval(1)) | (tod < interval(2));
                        end
                        vals = tt.value(mask);
                        % bin to 5 minutes across days
                        todSel = tod(mask);
                        bins = round(todSel/5)*5;
                        [~,~,ib] = unique(bins);
                        cgmUnique = accumarray(ib, vals, [], @mean);
                        val = std(cgmUnique, 'omitnan');
                    else
                        mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                        vals = tt.value(mask);
                        val = std(vals, 'omitnan');
                    end
                else
                    % retime to uniform 5-min grid then compute SD
                    try
                        tt5 = retime(tt, 'regular', @mean, 'TimeStep', minutes(5));
                        vals = tt5.value;
                    catch
                        vals = tt.value;
                    end
                    val = std(vals, 'omitnan');
                end
            end
        end

        function val = getGlucoseCV(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getGlucoseCV(interval, intervalIsDaily)), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = NaN;
            if isempty(obj)
                return;
            end
            if ~isempty(obj.cgm)
                tt = obj.cgm;
                if obj.useBG && ~isempty(obj.bg)
                    tt = obj.bg;
                end
                if ~isempty(interval)
                    if intervalIsDaily
                        tod = minutes(timeofday(tt.time));
                        if interval(2) > interval(1)
                            mask = (tod >= interval(1)) & (tod < interval(2));
                        else
                            mask = (tod >= interval(1)) | (tod < interval(2));
                        end
                        vals = tt.value(mask);
                        % bin to 5 minutes across days
                        todSel = tod(mask);
                        bins = round(todSel/5)*5;
                        [~,~,ib] = unique(bins);
                        cgmUnique = accumarray(ib, vals, [], @mean);
                        val = 100 * std(cgmUnique, 'omitnan') / mean(cgmUnique, 'omitnan');
                    else
                        mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                        vals = tt.value(mask);
                        val = 100 * std(vals, 'omitnan') / mean(vals, 'omitnan');
                    end
                else
                    % retime to uniform 5-min grid then compute CV
                    try
                        tt5 = retime(tt, 'regular', @mean, 'TimeStep', minutes(5));
                        vals = tt5.value;
                    catch
                        vals = tt.value;
                    end
                    val = 100 * std(vals, 'omitnan') / mean(vals, 'omitnan');
                end
            end
        end

        function val = getInsulinCV(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getInsulinCV(interval, intervalIsDaily)), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = NaN;
            if ~isempty(obj.basalRate)
                tt = obj.basalRate;
                if ~isempty(interval)
                    if intervalIsDaily
                        tod = minutes(timeofday(tt.time));
                        if interval(2) > interval(1)
                            mask = (tod >= interval(1)) & (tod < interval(2));
                        else
                            mask = (tod >= interval(1)) | (tod < interval(2));
                        end
                        vals = tt.value(mask);
                        % bin to 5 minutes across days
                        todSel = tod(mask);
                        bins = round(todSel/5)*5;
                        [~,~,ib] = unique(bins);
                        insUnique = accumarray(ib, vals, [], @mean);
                        val = 100 * std(insUnique, 'omitnan') / mean(insUnique, 'omitnan');
                    else
                        mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                        vals = tt.value(mask);
                        val = 100 * std(vals, 'omitnan') / mean(vals, 'omitnan');
                    end
                else
                    % retime to uniform 5-min grid then compute CV
                    try
                        tt5 = retime(tt, 'regular', @mean, 'TimeStep', minutes(5));
                        vals = tt5.value;
                    catch
                        vals = tt.value;
                    end
                    val = 100 * std(vals, 'omitnan') / mean(vals, 'omitnan');
                end
            end
        end

        function val = getTotalCarbActual(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getTotalCarbActual()), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = 0;
            if isempty(obj.carbsActual) && ~isempty(obj.carbs)
                carbActual_ = obj.carbs;
            else
                carbActual_ = obj.carbsActual;
            end
            if ~isempty(carbActual_)
                val = sum(carbActual_.value);
            end
        end

        function val = getTotalCarb(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getTotalCarb()), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = 0;
            if ~isempty(obj.carbs)
                val = sum(obj.carbs.value);
            end
        end

        function val = getNumCarb(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getNumCarb()), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = 0;
            if ~isempty(obj.carbs)
                val = sum(obj.carbs.value > 0);
            end
        end

        function val = getNumCarbActual(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getNumCarbActual()), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = 0;
            if ~isempty(obj.carbsActual)
                val = sum(obj.carbsActual.value > 0);
            end
        end

        function val = getTotalTreat(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getTotalTreat()), obj, 'UniformOutput', false);
                val = [val{:}];
                return;
            end
            val = 0;
            if ~isempty(obj.treat)
                val = sum(obj.treat.value);
            end
        end

        function val = getTotalBasal(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getTotalBasal(interval, intervalIsDaily)), obj);
                return;
            end
            if ~isempty(interval)
                val = 0;
                if ~isempty(obj.basalRate)
                    tt = obj.basalRate;
                    if height(tt) > 1
                        contrib = [hours(diff(tt.time)); hours(0)] .* tt.value; % units
                        if intervalIsDaily
                            tod = minutes(timeofday(tt.time));
                            if interval(2) > interval(1)
                                mask = (tod >= interval(1)) & (tod < interval(2));
                            else
                                mask = (tod >= interval(1)) | (tod < interval(2));
                            end
                        else
                            mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                        end
                        val = val + sum(contrib(mask));
                    end
                end
                if ~isempty(obj.basalInj)
                    tt = obj.basalInj;
                    if intervalIsDaily
                        tod = minutes(timeofday(tt.time));
                        if interval(2) > interval(1)
                            mask = (tod >= interval(1)) & (tod < interval(2));
                        else
                            mask = (tod >= interval(1)) | (tod < interval(2));
                        end
                    else
                        mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                    end
                    if any(mask)
                        val = val + sum(tt.value(mask));
                    end
                end
            else
                val = 0;
                if ~isempty(obj.basalRate)
                    tt = obj.basalRate;
                    if height(tt) > 1
                        val = val + sum(hours(diff(tt.time)) .* tt.value(1:end-1));
                    end
                end
                if ~isempty(obj.basalInj)
                    val = val + sum(obj.basalInj.value);
                end
            end
        end

        function val = getTotalBolus(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getTotalBolus(interval, intervalIsDaily)), obj);
                return;
            end
            val = 0;
            if isempty(obj.bolus)
                return;
            end
            if ~isempty(interval)
                tt = obj.bolus;
                if intervalIsDaily
                    tod = minutes(timeofday(tt.time));
                    if interval(2) > interval(1)
                        mask = (tod >= interval(1)) & (tod < interval(2));
                    else
                        mask = (tod >= interval(1)) | (tod < interval(2));
                    end
                else
                    mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                end
                val = val + sum(tt.value(mask));
            else
                val = val + sum(obj.bolus.value);
            end
        end

        function val = getTotalCarbBolus(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getTotalCarbBolus(interval, intervalIsDaily)), obj);
                return;
            end
            val = 0;
            if isempty(obj.bolusCarb)
                return;
            end
            if ~isempty(interval)
                tt = obj.bolusCarb;
                if intervalIsDaily
                    tod = minutes(timeofday(tt.time));
                    if interval(2) > interval(1)
                        mask = (tod >= interval(1)) & (tod < interval(2));
                    else
                        mask = (tod >= interval(1)) | (tod < interval(2));
                    end
                else
                    mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                end
                val = val + sum(tt.value(mask));
            else
                val = val + sum(obj.bolusCarb.value);
            end
        end

        function val = getTotalCorrBolus(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getTotalCorrBolus(interval, intervalIsDaily)), obj);
                return;
            end
            val = 0;
            if isempty(obj.bolusCorr)
                return;
            end
            if ~isempty(interval)
                tt = obj.bolusCorr;
                if intervalIsDaily
                    tod = minutes(timeofday(tt.time));
                    if interval(2) > interval(1)
                        mask = (tod >= interval(1)) & (tod < interval(2));
                    else
                        mask = (tod >= interval(1)) | (tod < interval(2));
                    end
                else
                    mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                end
                val = val + sum(tt.value(mask));
            else
                val = val + sum(obj.bolusCorr.value);
            end
        end

        function val = getTotalInsulin(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            val = obj.getTotalBolus(interval, intervalIsDaily) + obj.getTotalBasal(interval, intervalIsDaily);
        end

        function val = getDailyInsulin(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            val = obj.getDailyBolus(interval, intervalIsDaily) + obj.getDailyBasal(interval, intervalIsDaily);
        end

        function val = getDailyBasal(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getDailyBasal(interval, intervalIsDaily)), obj);
                return;
            end

            % if obj.duration > days(3)
            %     startDate_ = floor(obj.startDate);
            % else
            if ~isempty(obj.basalInj)
                startTimestamp_ = obj.basalInj.time(1);
            elseif ~isempty(obj.basalRate)
                startTimestamp_ = obj.basalRate.time(1);
            else
                val = 0;
                return;
            end
            % end

            val = 0;
            if ~isempty(obj.basalInj)
                tt = obj.basalInj;
                basalTime_ = tt.time;
                basal_ = tt.value;
                if ~isempty(interval)
                    if intervalIsDaily
                        tod = minutes(timeofday(tt.time));
                        if interval(2) > interval(1)
                            mask = (tod >= interval(1)) & (tod < interval(2));
                        else
                            mask = (tod >= interval(1)) | (tod < interval(2));
                        end
                    else
                        mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                    end
                    basal_ = basal_(mask);
                    basalTime_ = basalTime_(mask);
                end

                days_ = floor(days(basalTime_ - dateshift(obj.startDate, 'start', 'day')));
                dailyBasal = sum((days_ == unique(days_)').*basal_);
                dailyBasal(~any(days_ == unique(days_)')) = [];
                dailyBasal = rmoutliers(dailyBasal);
                val = mean(dailyBasal);
            elseif ~isempty(obj.basalRate)
                tt = obj.basalRate;
                basalTime_ = tt.time;
                basal_ = tt.value;
                if ~isempty(interval)
                    if intervalIsDaily
                        tod = minutes(timeofday(tt.time));
                        if interval(2) > interval(1)
                            mask = (tod >= interval(1)) & (tod < interval(2));
                        else
                            mask = (tod >= interval(1)) | (tod < interval(2));
                        end
                    else
                        mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                    end
                    basal_ = basal_(mask);
                    basalTime_ = basalTime_(mask);
                end

                days_ = floor(days(basalTime_(1:end - 1) - startTimestamp_));
                if ~isempty(days_)
                    timeDiffs = days(diff(basalTime_));
                    dailyBasal = sum((days_ == unique(days_)').*timeDiffs.*basal_(1:end - 1)./(sum((days_ == unique(days_)').*timeDiffs)));
                    val = mean(dailyBasal);
                end
            end
        end

        function val = getNumberOfBolus(obj, thresh, interval, intervalIsDaily)
            if nargin < 2
                thresh = 0.0;
            end
            if nargin < 3
                interval = [];
            end
            if nargin < 4
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getNumberOfBolus(thresh, interval, intervalIsDaily)), obj);
                return;
            end
            val = 0;
            if isempty(obj.bolus)
                return;
            end
            tt = obj.bolus;
            if ~isempty(interval)
                if intervalIsDaily
                    tod = minutes(timeofday(tt.time));
                    if interval(2) > interval(1)
                        mask = (tod >= interval(1)) & (tod < interval(2));
                    else
                        mask = (tod >= interval(1)) | (tod < interval(2));
                    end
                else
                    mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                end
                val = val + sum(tt.value(mask) > thresh);
            else
                val = val + sum(tt.value > thresh);
            end
        end

        function val = getNumberOfCarbBolus(obj, thresh, interval, intervalIsDaily)
            if nargin < 2
                thresh = 0.0;
            end
            if nargin < 3
                interval = [];
            end
            if nargin < 4
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getNumberOfCarbBolus(thresh, interval, intervalIsDaily)), obj);
                return;
            end
            val = 0;
            if isempty(obj.bolusCarb)
                return;
            end
            tt = obj.bolusCarb;
            if ~isempty(interval)
                if intervalIsDaily
                    tod = minutes(timeofday(tt.time));
                    if interval(2) > interval(1)
                        mask = (tod >= interval(1)) & (tod < interval(2));
                    else
                        mask = (tod >= interval(1)) | (tod < interval(2));
                    end
                else
                    mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                end
                val = val + sum(tt.value(mask) > thresh);
            else
                val = val + sum(tt.value > thresh);
            end
        end

        function val = getNumberOfCorrBolus(obj, thresh, interval, intervalIsDaily)
            if nargin < 2
                thresh = 0.0;
            end
            if nargin < 3
                interval = [];
            end
            if nargin < 4
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getNumberOfCorrBolus(thresh, interval, intervalIsDaily)), obj);
                return;
            end
            val = 0;
            if isempty(obj.bolusCorr)
                return;
            end
            tt = obj.bolusCorr;
            if ~isempty(interval)
                if intervalIsDaily
                    tod = minutes(timeofday(tt.time));
                    if interval(2) > interval(1)
                        mask = (tod >= interval(1)) & (tod < interval(2));
                    else
                        mask = (tod >= interval(1)) | (tod < interval(2));
                    end
                else
                    mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                end
                val = val + sum(tt.value(mask) > thresh);
            else
                val = val + sum(tt.value > thresh);
            end
        end

        function val = getNumberOfBolusAfterCarb(obj, thresh)
            if nargin < 2
                thresh = 0;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getNumberOfBolusAfterCarb(thresh)), obj);
                return;
            end
            val = 0;
            if ~isempty(obj.bolus)
                bolusTime = obj.bolus.time(obj.bolus.value > thresh);
                % bolusValue = obj.bolus.value(obj.bolus.value > thresh);
                carbTime = obj.carbsActual.time(obj.carbsActual.value > 0);
                cnt = 0;
                for k = 1:length(bolusTime)
                    timeDiffMinutes = minutes(bolusTime(k) - carbTime);
                    if any(timeDiffMinutes < 120 & timeDiffMinutes >= -30)
                        cnt = cnt + 1;
                        % disp(find(timeDiffMinutes < 90 & timeDiffMinutes >= -30))
                    else
                        % disp(bolusValue(k))
                        % disp(minutes(timeofday(bolusTime(k))))
                        % disp(minutes(timeofday(carbTime)))
                    end
                end
                val = val + cnt;
            end
        end

        function val = getDailySema(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getDailySema(interval, intervalIsDaily)), obj);
                return;
            end

            % if obj.duration > days(3)
            %     startDate_ = floor(obj.startDate);
            % else
            if ~isempty(obj.semaInj)
                startTimestamp_ = obj.semaInj.time(1);
            else
                val = 0;
                return;
            end
            % end

            val = 0;
            if ~isempty(obj.semaInj)
                tt = obj.semaInj;
                semaTime_ = tt.time;
                sema_ = tt.value;
                if ~isempty(interval)
                    if intervalIsDaily
                        tod = minutes(timeofday(tt.time));
                        if interval(2) > interval(1)
                            mask = (tod >= interval(1)) & (tod < interval(2));
                        else
                            mask = (tod >= interval(1)) | (tod < interval(2));
                        end
                    else
                        mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                    end
                    sema_ = sema_(mask);
                    semaTime_ = semaTime_(mask);
                end

                days_ = floor(days(semaTime_ - dateshift(obj.startDate, 'start', 'day')));
                dailySema = sum((days_ == unique(days_)').*sema_);
                dailySema(~any(days_ == unique(days_)')) = [];
                dailySema = rmoutliers(dailySema);
                val = mean(dailySema);
            end
        end

        function val = getDailyBolus(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getDailyBolus(interval, intervalIsDaily)), obj);
                return;
            end
            if obj.duration > days(3)
                startTimestamp_ = dateshift(obj.startDate, 'start', 'day');
            elseif ~isempty(obj.bolus)
                startTimestamp_ = obj.bolus.time(1);
            end

            val = 0;
            if ~isempty(obj.bolus)
                tt = obj.bolus;
                bolusTime_ = tt.time;
                bolus_ = tt.value;
                if ~isempty(interval)
                    if intervalIsDaily
                        tod = minutes(timeofday(tt.time));
                        if interval(2) > interval(1)
                            mask = (tod >= interval(1)) & (tod < interval(2));
                        else
                            mask = (tod >= interval(1)) | (tod < interval(2));
                        end
                    else
                        mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                    end
                    bolus_ = bolus_(mask);
                    bolusTime_ = bolusTime_(mask);
                end

                if ~isempty(bolus_)
                    val = sum(bolus_)/days(obj.duration);
                end
            end
        end

        function val = getDailyCarb(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getDailyCarb(interval, intervalIsDaily)), obj);
                return;
            end
            val = 0;
            if ~isempty(obj.carbs)
                tt = obj.carbs;
                carbTime_ = tt.time;
                carb_ = tt.value;
                if ~isempty(interval)
                    if intervalIsDaily
                        tod = minutes(timeofday(tt.time));
                        if interval(2) > interval(1)
                            mask = (tod >= interval(1)) & (tod < interval(2));
                        else
                            mask = (tod >= interval(1)) | (tod < interval(2));
                        end
                    else
                        mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                    end
                    carb_ = carb_(mask);
                    carbTime_ = carbTime_(mask);
                end

                if ~isempty(carb_)
                    val = sum(carb_)/days(obj.duration);
                end
            end
        end

        function val = getDailyCarbActual(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getDailyCarbActual(interval, intervalIsDaily)), obj);
                return;
            end
            val = NaN;
            if isempty(obj.carbsActual) && ~isempty(obj.carbs)
                carbActual_ = obj.carbs;
            else
                carbActual_ = obj.carbsActual;
            end
            if ~isempty(carbActual_)
                carbTime_ = carbActual_.time;
                carb_ = carbActual_.value;
                if ~isempty(interval)
                    if intervalIsDaily
                        tod = minutes(timeofday(carbActual_.time));
                        if interval(2) > interval(1)
                            mask = (tod >= interval(1)) & (tod < interval(2));
                        else
                            mask = (tod >= interval(1)) | (tod < interval(2));
                        end
                    else
                        mask = (carbActual_.time >= interval(1)) & (carbActual_.time < interval(2));
                    end
                    carb_ = carb_(mask);
                    carbTime_ = carbTime_(mask);
                end

                if ~isempty(carb_)
                    val = sum(carb_)/days(obj.duration);
                end
            end
        end

        function val = getTotalCarbAnnounced(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getTotalCarbAnnounced()), obj);
                return;
            end
            events_ = [];
            if ~isempty(obj.carbsActual)
                events_ = obj.carbsActual.value;
            end
            if ~isempty(obj.carbs)
                events_ = obj.carbs.value;
            end
            if ~isempty(obj.carbsCategory)
                events_ = obj.carbsCategory.value;
            end
            val = sum(events_ > 0);
        end

        function val = getDailyTreat(obj, interval, intervalIsDaily)
            if nargin < 2
                interval = [];
            end
            if nargin < 3
                intervalIsDaily = true;
            end
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getDailyTreat(interval, intervalIsDaily)), obj);
                return;
            end
            val = 0;
            if ~isempty(obj.treat)
                tt = obj.treat;
                treatTime_ = tt.time;
                treat_ = tt.value;
                if ~isempty(interval)
                    if intervalIsDaily
                        tod = minutes(timeofday(tt.time));
                        if interval(2) > interval(1)
                            mask = (tod >= interval(1)) & (tod < interval(2));
                        else
                            mask = (tod >= interval(1)) | (tod < interval(2));
                        end
                    else
                        mask = (tt.time >= interval(1)) & (tt.time < interval(2));
                    end
                    treat_ = treat_(mask);
                    treatTime_ = treatTime_(mask);
                end

                if ~isempty(treat_)
                    val = sum(treat_)/days(obj.duration);
                end
            end
        end

        function [val, time] = getDailyCarbRatio(obj, time)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getDailyCarbRatio(time)), obj, 'UniformOutput', false);
                time = [];
                return;
            end

            val = NaN;
            if ~isempty(obj.carbRatio)
                [carbRatiosTimeUnique, carbRatiosValUnique] = obj.extractUniqueDailyValue(obj.carbRatio);

                if nargin < 2
                    val = carbRatiosValUnique([true; abs(diff(carbRatiosValUnique)) > 0]);
                    time = carbRatiosTimeUnique([true; abs(diff(carbRatiosValUnique)) > 0]);

                    if length(val) > 1 && val(end) == val(1)
                        val(1) = [];
                        time(1) = [];
                    elseif length(val) == 1
                        time = 0;
                    end
                else
                    val = nan(size(time));
                    for k = 1:length(time)
                        if k < length(time)
                            idx = find(carbRatiosTimeUnique >= time(k) & carbRatiosTimeUnique < time(k+1));
                        else
                            idx = find(carbRatiosTimeUnique >= time(k) & carbRatiosTimeUnique < time(1)+1440);
                        end
                        if ~isempty(idx)
                            val(k) = median(carbRatiosValUnique(idx));
                        else
                            idx = find(carbRatiosTimeUnique <= time(k), 1, 'last');
                            if ~isempty(idx)
                                val(k) = carbRatiosValUnique(idx);
                            end
                        end
                    end

                    val = fillmissing(val, 'previous');
                    val(isnan(val)) = val(end);
                end
            else
                time = [];
            end
        end

        function [val, time] = getDailyPumpBasal(obj, time)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getDailyPumpBasal(time)), obj, 'UniformOutput', false);
                time = [];
                return;
            end

            val = NaN;
            if ~isempty(obj.pumpBasal)
                [pumpBasalsTimeUnique, pumpBasalsValUnique] = obj.extractUniqueDailyValue(obj.pumpBasal);

                if nargin < 2
                    val = pumpBasalsValUnique([true; abs(diff(pumpBasalsValUnique)) > 0]);
                    time = pumpBasalsTimeUnique([true; abs(diff(pumpBasalsValUnique)) > 0]);

                    if length(val) > 1 && val(end) == val(1)
                        val(1) = [];
                        time(1) = [];
                    elseif isscalar(val)
                        time = 0;
                    end
                else
                    val = nan(size(time));
                    for k = 1:length(time)
                        if k < length(time)
                            idx = find(pumpBasalsTimeUnique >= time(k) & pumpBasalsTimeUnique < time(k+1));
                        else
                            idx = find(pumpBasalsTimeUnique >= time(k) & pumpBasalsTimeUnique < time(1)+1440);
                        end
                        if ~isempty(idx)
                            val(k) = median(pumpBasalsValUnique(idx));
                        else
                            idx = find(pumpBasalsTimeUnique <= time(k), 1, 'last');
                            if ~isempty(idx)
                                val(k) = pumpBasalsValUnique(idx);
                            end
                        end
                    end

                    val = fillmissing(val, 'previous');
                    val(isnan(val)) = val(end);
                end
            else
                time = [];
            end
        end

        function [val, time] = getDailyInsulinSensitivity(obj, time)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getDailyInsulinSensitivity(time)), obj, 'UniformOutput', false);
                time = [];
                return;
            end

            val = NaN;
            if ~isempty(obj.insulinSensitivity)
                [insulinSensitivityTimeUnique, insulinSensitivityValUnique] = obj.extractUniqueDailyValue(obj.insulinSensitivity);

                if nargin < 2
                    val = insulinSensitivityValUnique([true; abs(diff(insulinSensitivityValUnique)) > 0]);
                    time = insulinSensitivityTimeUnique([true; abs(diff(insulinSensitivityValUnique)) > 0]);

                    if length(val) > 1 && val(end) == val(1)
                        val(1) = [];
                        time(1) = [];
                    elseif isscalar(val)
                        time = 0;
                    end
                else
                    val = nan(size(time));
                    for k = 1:length(time)
                        if k < length(time)
                            idx = find(insulinSensitivityTimeUnique >= time(k) & insulinSensitivityTimeUnique < time(k+1));
                        else
                            idx = find(insulinSensitivityTimeUnique >= time(k) & insulinSensitivityTimeUnique < time(1)+1440);
                        end
                        if ~isempty(idx)
                            val(k) = median(insulinSensitivityValUnique(idx));
                        else
                            idx = find(insulinSensitivityTimeUnique <= time(k), 1, 'last');
                            if ~isempty(idx)
                                val(k) = insulinSensitivityValUnique(idx);
                            end
                        end
                    end

                    val = fillmissing(val, 'previous');
                    val(isnan(val)) = val(end);
                end
            else
                time = [];
            end
        end

        function [val, time] = getDailyBasalInjection(obj)
            if numel(obj) > 1
                val = arrayfun(@(e)(e.getDailyBasalInjection()), obj, 'UniformOutput', false);
                time = [];
                return;
            end

            val = NaN;
            if ~isempty(obj.basalInj)
                tt = obj.basalInj;
                basalInjsTime = minutes(timeofday(tt.time));
                basalTimeClock = angle(cos(2 * pi * basalInjsTime / 1440)+1i*sin(2 * pi * basalInjsTime / 1440)) * 1440 / (2 * pi);

                % check if 2 clusters are possible
                if length(basalTimeClock) < 2
                    usualBasalTime = mod(basalTimeClock, 1440);
                else
                    warning('off', 'stats:kmeans:FailedToConverge');
                    [~, CC] = kmeans(basalTimeClock, 2, 'MaxIter', 10);
                    if abs(diff(CC)) < 6 * 60
                        usualBasalTime = mod(mean(basalTimeClock), 1440);
                    else
                        usualBasalTime = mod(CC, 1440);
                    end
                end

                [~, idxClosest] = min(abs(basalInjsTime - usualBasalTime(:)'), [], 2);
                for k = length(usualBasalTime):-1:1
                    usualBasalVal(k) = sum(tt.value(idxClosest == k)) / numel(unique(floor(days(tt.time(idxClosest == k) - tt.time(1)))));
                end

                val = usualBasalVal(:);
                time = round(usualBasalTime(:));

                [time, idxSorted] = sort(time);
                val = val(idxSorted);
            else
                time = [];
            end
        end
    end

    % Dependent arguments
    methods
        function val = get.id(obj)
            val = regexp(obj.name, '\d+', 'match');
            if ~isempty(val)
                val = str2double(val{1});
            else
                val = [];
            end
        end

        function obj = set.id(obj, val)
            obj.name = sprintf('P%03d', val);
        end

        function val = get.BMI(obj)
            val = obj.BW / (obj.BH/100)^2;
        end

        function val = get.TDIPerBW(obj)
            val = obj.TDI / obj.BW;
        end

        function val = get.isEmpty(obj)
            val = isnat(obj.startDate);
        end

        function val = get.figHandle(obj)
            val = mod(prod(obj.name + 0), 104729);
        end

        function val = get.startDate(obj)
            % earliest datetime across available timetable series
            val = NaT;
            for fn = obj.timeSeriesFields
                ts = obj.(fn{1});
                if ~isempty(ts)
                    t0 = ts.time(1);
                    if isnat(val)
                        val = t0;
                    else
                        val = min(val, t0);
                    end
                end
            end
        end

        function val = get.endDate(obj)
            % latest datetime across available timetable series
            val = NaT;
            for fn = obj.timeSeriesFields
                ts = obj.(fn{1});
                if istimetable(ts) && ~isempty(ts)
                    t1 = ts.time(end);
                    if isnat(val)
                        val = t1;
                    else
                        val = max(val, t1);
                    end
                end
            end
        end

        function val = get.startTimeInMinutes(obj)
            % minutes since midnight of startDate
            if isnat(obj.startDate)
                val = NaN;
            else
                tod = timeofday(obj.startDate);
                val = hours(tod)*60 + minutes(tod) + seconds(tod)/60;
            end
        end

        function val = get.endTimeInMinutes(obj)
            % minutes since midnight of endDate
            if isnat(obj.endDate)
                val = NaN;
            else
                tod = timeofday(obj.endDate);
                val = hours(tod)*60 + minutes(tod) + seconds(tod)/60;
            end
        end

        function val = get.duration(obj)
            if isnat(obj.startDate) || isnat(obj.endDate)
                val = days(0);
            else
                val = obj.endDate - obj.startDate; % duration
            end
        end

        function val = get.durationCGM(obj)
            % Estimated CGM coverage in days based on sampling gaps
            val = minutes(0);
            if ~isempty(obj.cgm)
                if istimetable(obj.cgm)
                    dt = minutes(diff(obj.cgm.time));
                    if ~isempty(dt)
                        med = median(dt, 'omitnan');
                        dt(dt > 10*med) = [];
                        val = days(sum(dt)/60/24);
                    end
                end
            end
        end

        function val = get.daysCount(obj)
            if isnat(obj.startDate) || isnat(obj.endDate)
                val = 0;
                return;
            end
            sd = dateshift(obj.startDate, 'start', 'day');
            ed = dateshift(obj.endDate - seconds(eps), 'start', 'day');
            val = days(ed - sd) + 1;
        end

        function set.startDate(obj, val)
            % Trim all timetable series to start at or after the provided datetime
            for fn = obj.fields
                ts = obj.(fn{1});
                if ~isempty(ts)
                    mask = ts.time < val;
                    ts(mask, :) = [];
                    obj.(fn{1}) = ts;
                end
            end
            if ~isempty(obj.raw)
                obj.raw = [];
            end
        end

        function set.endDate(obj, val)
            % Trim all timetable series to end at or before the provided datetime
            for fn = obj.fields
                ts = obj.(fn{1});
                if istimetable(ts) && ~isempty(ts)
                    mask = ts.time > val;
                    ts(mask, :) = [];
                    obj.(fn{1}) = ts;
                end
            end
            if ~isempty(obj.raw)
                obj.raw = [];
            end
        end
    end

    methods (Static)
        outcomes = computeOutcomes(subjs, varargin);
        fig = plotOutcomes(subjs, varargin);
        [fig, analyzedGroup] = plotCompare(subjs, varargin);
        fig = compareAGP(subj1, subj2, varargin);
        [ax1, varargout] = compareMetrics(subjs, varargin);

        function out = jsonToStruct(filename)
            f = fopen(filename, 'r');
            if f > 0
                out = jsondecode(char(fread(f)'));
                fclose(f);
            else
                warning('File %s not found', filename);
                out = [];
            end
        end

        function structToJson(data,filename)
            str = jsonencode(data, "PrettyPrint", true);

            filepath = fileparts(filename);
            if ~isempty(filepath) && exist(filepath, 'dir') ~= 7
                mkdir(filepath);
            end

            fid = fopen(filename, 'w');
            fwrite(fid, str);
            fclose(fid);
        end

        function subj = merge(subjGrp, varargin)
            if ~iscell(subjGrp)
                subjGrp = num2cell(subjGrp);
            end

            popSize = unique(cellfun(@numel, subjGrp));
            if numel(popSize) > 1
                fprintf('[DIAX][merge] subjGrp should have the same number of DIAXs!\n');
                return;
            end

            if popSize > 1
                subj_ = arrayfun(@(a)(DIAX.merge(cellfun(@(c)(c(a)), subjGrp, 'UniformOutput', false))), 1:popSize, 'UniformOutput', false);
                subj = [subj_{:}];
                return;
            end

            subj = [subjGrp{:}]';
            subj = subj.combine();
        end

        function [path_, name_] = ensureFolder(fullpath, defautname)
            if fullpath(end) == '/' || fullpath(end) == '\'
                path_ = fullpath;
                name_ = defautname;
            else
                [path_, name_] = fileparts(fullpath);
            end

            if ~isempty(path_)
                if exist(path_, 'dir') ~= 7
                    mkdir(path_);
                end
            else
                path_ = '.';
            end

            if path_(end) ~= '/' || path_(end) ~= '\'
                path_(end+1) = '/';
            end
        end
    end

    methods (Access = protected)
        % Override copyElement method:
        function cpObj = copyElement(obj)
            % Make a shallow copy of all four properties
            cpObj = copyElement@matlab.mixin.Copyable(obj);
        end
    end
end
