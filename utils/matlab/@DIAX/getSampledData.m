function data = getSampledData(obj, sampleTime, varargin)
if numel(obj) > 1
    data = arrayfun(@(e)(e.getSampledData(sampleTime, varargin{:})), obj, 'UniformOutput', false);
    numOfFields = cellfun(@(c)(numel(fieldnames(c))), data);
    data(numOfFields ~= mode(numOfFields)) = [];
    data = [data{:}];
    return;
end

prefill_ = false;
postfill_ = false;
fn = obj.timeSeriesFields;
cropToCGM = false;
maxCGMGapTime_ = 1.5 * 60;
maxBasalGapTime_ = 24 * 60;
startTime_ = [];
duration_ = [];
method_ = 'pchip';
for nVar = 1:2:length(varargin)
    switch lower(varargin{nVar})
        case {'gap', 'maxgap', 'maxgaptime', 'cgmgap'}
            maxCGMGapTime_ = floor(varargin{nVar + 1}/sampleTime) * sampleTime;
        case {'basalgap'}
            maxBasalGapTime_ = floor(varargin{nVar + 1}/sampleTime) * sampleTime;
        case 'starttime'
            startTime_ = floor(varargin{nVar + 1}/sampleTime) * sampleTime;
        case 'duration'
            duration_ = floor(varargin{nVar + 1}/sampleTime) * sampleTime;
        case 'method'
            method_ = varargin{nVar + 1};
        case {'cropcgm', 'crop'}
            cropToCGM = varargin{nVar + 1};
        case {'fields', 'field'}
            fn = intersect(properties(obj)', varargin{nVar + 1});
        case {'prefill', 'pre'}
            postfill_ = varargin{nVar + 1};
        case {'postfill', 'post'}
            prefill_ = varargin{nVar + 1};
        case {'fill'}
            postfill_ = varargin{nVar + 1};
            prefill_ = varargin{nVar + 1};
    end
end

if obj.isEmpty
    data = struct();
    return;
end

data.name = obj.name;
data.stepTime = sampleTime;

if cropToCGM
    firstCGMTime = minutes(obj.cgm.time(1) - dateshift(obj.startDate, 'start', 'day'));
    lastCGMTime = minutes(obj.cgm.time(end) - dateshift(obj.startDate, 'start', 'day'));
    data.time = floor(firstCGMTime/sampleTime) * sampleTime:sampleTime:(ceil((lastCGMTime + 1e-6) / sampleTime) - 1) * sampleTime;
    data.time = round(data.time(:));
else
    firstTime = minutes(obj.startDate - dateshift(obj.startDate, 'start', 'day'));
    lastTime = minutes(obj.endDate - dateshift(obj.startDate, 'start', 'day'));
    data.time = floor(firstTime/sampleTime) * sampleTime:sampleTime:(ceil((lastTime + 1e-6) / sampleTime) - 1) * sampleTime;
    data.time = round(data.time(:));
end

if ~isempty(startTime_)
    if mod(data.time(1), 1440) > startTime_ && mod(data.time(1), 1440) < startTime_ + 24 * 60
        data.time = [((data.time(1) + startTime_ - mod(data.time(1), 1440)):sampleTime:(data.time(1) - sampleTime))'; data.time];
    end
    if mod(data.time(1), 1440) < startTime_ && mod(data.time(1), 1440) > startTime_ - 24 * 60
        idxStart = (startTime_ - mod(data.time(1), 1440))/sampleTime + 1;
        data.time(1:idxStart - 1) = [];
    end
end

if ~isempty(duration_)
    if minutes(length(data.time)*sampleTime) < duration_
        data.time = [data.time; ((data.time(end) + sampleTime):sampleTime:(data.time(1) + minutes(duration_) - sampleTime))'];
    end
    if minutes(length(data.time)*sampleTime) > duration_
        idxLast = minutes(duration_)/sampleTime;
        data.time(idxLast+1:end) = [];
    end
end

data.timestamp = dateshift(obj.startDate, 'start', 'day') + minutes(data.time);
data.startDate = dateshift(obj.startDate, 'start', 'day') + minutes(data.time(1));
data.endDate = dateshift(obj.startDate, 'start', 'day') + minutes(data.time(end));

data.startTime = mod(data.time(1), 1440);
data.length = length(data.time);
data.duration = minutes(data.length*sampleTime);
data.durationCGM = obj.durationCGM;

if ~iscell(fn)
    fn = {fn};
end

for k = 1:length(fn)
    if isempty(obj.(fn{k}))
        switch fn{k}
            case 'cgm'
                data.(fn{k}) = nan(size(data.time));
            otherwise
                data.(fn{k}) = zeros(size(data.time));
        end
        continue;
    end

    switch fn{k}
        case {'cgm', 'bg'}
            tt = obj.(fn{k});
            val_ = tt.value;
            time_ = minutes(tt.time - dateshift(obj.startDate, 'start', 'day'));
            if strcmp(fn{k}, 'cgm')
                val_(val_ < 40) = 39;
                val_(val_ > 400) = 401;
            end
            matHelper_ = sparse([]);
            for ii = 1:1e4:length(data.time)
                matHelper_ = [matHelper_, sparse(abs(data.time(ii:min(length(data.time), ii+1e4-1))' - time_) <= sampleTime / 2)];
            end
            data.(fn{k}) = full(nansum(val_.*matHelper_, 1) ./ nansum(matHelper_, 1));

            % replace intial nan values by first non-nan
            idxFirstNonNaN = find(~isnan(data.(fn{k})), 1);
            if prefill_
                data.(fn{k})(1:idxFirstNonNaN - 1) = data.(fn{k})(idxFirstNonNaN);
            end

            idxLastNonNaN = find(~isnan(data.(fn{k})), 1, 'last');
            if postfill_
                data.(fn{k})(idxLastNonNaN + 1:end) = data.(fn{k})(idxLastNonNaN);
            end

            if maxCGMGapTime_ > 0
                if (~prefill_ && ~postfill_ && any(isnan(data.(fn{k})(idxFirstNonNaN:idxLastNonNaN)))) ||  ...
                        (~prefill_ && postfill_ && any(isnan(data.(fn{k})(idxFirstNonNaN:end)))) || ...
                        (prefill_ && ~postfill_ && any(isnan(data.(fn{k})(1:idxLastNonNaN)))) || ...
                        (prefill_ && postfill_ && any(isnan(data.(fn{k}))))

                    % interpolate all
                    data.(fn{k}) = fillmissing(data.(fn{k}), method_);

                    % puts back prefill/postfill
                    if ~prefill_
                        data.(fn{k})(1:idxFirstNonNaN-1) = NaN;
                    end
                    if ~postfill_
                        data.(fn{k})(idxLastNonNaN+1:end) = NaN;
                    end

                    % puts back large gaps
                    indGapStart = find(round(diff(time_)/sampleTime)*sampleTime > maxCGMGapTime_);
                    indGap = [];
                    for n = 1:numel(indGapStart)
                        indGap = [indGap; find(data.time > time_(indGapStart(n)) & data.time < time_(indGapStart(n) + 1))];
                    end
                    data.(fn{k})(indGap) = NaN;
                end
            end

        case {'basalRate', 'basalRateAuto', 'basalRateMax'}
            tt = obj.(fn{k});
            val_ = tt.value;
            time_ = minutes(tt.time - dateshift(obj.startDate, 'start', 'day'));
            if size(tt, 1) == 1
                data.(fn{k}) = val_(1) * ones(size(data.time));
            else
                % time_half_sampled = unique([data.time; data.time + data.stepTime/2; data.time - data.stepTime/2]);
                % bsalRate_half_sampled = interp1(time_, val_, time_half_sampled, 'previous');
                % data.(fn{k}) = bsalRate_half_sampled;
                data.(fn{k}) = interp1(time_, val_, data.time, 'previous');
            end

            % Fill NAN values if missing pump info
            if maxBasalGapTime_ > 0
                data.(fn{k}) = fillmissing(data.(fn{k}), 'previous');
                indGapStart = find(round(diff(time_)/sampleTime)*sampleTime > maxBasalGapTime_);
                indGap = [];
                for n = 1:numel(indGapStart)
                    indGap = [indGap; find(data.time > time_(indGapStart(n)) & data.time < time_(indGapStart(n) + 1))];
                end
                data.(fn{k})(indGap) = NaN;
                data.(fn{k})(data.time > time_(end)) = NaN;
            end

            if prefill_
                data.(fn{k}) = fillmissing(data.(fn{k}), 'next');
            end

            if postfill_
                data.(fn{k}) = fillmissing(data.(fn{k}), 'previous');
            end
        case {'pumpBasal', 'carbRatio', 'insulinSensitivity', 'fixedDose', 'glucoseTarget', 'tdi', 'tdiProgrammed'}
            tt = obj.(fn{k});
            val_ = tt.value;
            time_ = minutes(tt.time - dateshift(obj.startDate, 'start', 'day'));
            if size(tt, 1) == 1
                data.(fn{k}) = val_(1) * ones(size(data.time));
            else
                data.(fn{k}) = interp1(time_, val_, data.time, 'previous');
            end

        case {'carbs', 'carbsCategory', 'carbsAnnounced', 'carbsActual', 'carbCountedIndex', 'exercise',...
                'treat', 'bolus', 'bolusPumpBC', 'bolusAuto', 'bolusRecomm', 'bolusManual', 'bolusCarb', 'bolusCorr' ...
                'bolusMealRecomm', 'bolusCorrRecomm', 'intermedInj', 'basalInj', 'carbsType', 'hba1c'}
            tt = obj.(fn{k});
            val_ = tt.value;
            time_ = minutes(tt.time - dateshift(obj.startDate, 'start', 'day'));
            timeMat_ = data.time' - time_;
            data.(fn{k}) = sum(val_.*(timeMat_ >= -sampleTime / 2 & timeMat_ < sampleTime / 2), 1);

        case {'smbg', 'smbgFasting', 'fbg'}
            tt = obj.(fn{k});
            val_ = tt.value;
            time_ = minutes(tt.time - dateshift(obj.startDate, 'start', 'day'));
            timeMat_ = data.time' - time_;
            data.(fn{k}) = sum(val_.*(timeMat_ >= -sampleTime / 2 & timeMat_ < sampleTime / 2), 1)./sum(timeMat_ >= -sampleTime / 2 & timeMat_ < sampleTime / 2, 1);

        otherwise
            data.(fn{k}) = [];
            error('[Subject][getSampledData] Missing rule for %s', fn{k})
    end

    data.(fn{k}) = data.(fn{k})(:);
end

data.time = data.time - data.time(1);

data.BW = obj.BW;
data.TDIEst = obj.getTotalInsulin() / days(obj.durationCGM);
data.TBasalEst = obj.getTotalBasal() / days(obj.durationCGM);
data.TBolusEst = obj.getTotalBolus() / days(obj.durationCGM);
data.iobBolus = [];
data.mealBolus = [];

if isfield(data, 'bolus') && isfield(data, 'carbs')
    data.iobBolus = zeros(size(data.bolus));
    data.mealBolus = zeros(size(data.bolus));
    idxBoluses = find(data.bolus > 0);
    if ~isempty(idxBoluses)
        td = 6 * 60;
        tp = 75;

        for n = 1:length(data.iobBolus)
            for idx = idxBoluses(data.time(idxBoluses) < data.time(n) & data.time(n) < data.time(idxBoluses)+td)'
                dt = data.time(n) - data.time(idx);
                data.iobBolus(n) = data.iobBolus(n) + data.bolus(idx) * (1 - dt/td);
            end
        end

        if ~isfield(data, 'carbRatio') || isempty(data.carbRatio)
            allEventsIdx = unique(find((data.bolus > 0 | data.carbs > 0) & ~isnan(data.cgm)));
            allEventsTime = data.time(allEventsIdx);
            groupedEvents = cumsum([true; diff(allEventsTime) > 35]);
            groupedEvents = (groupedEvents == (1:max(groupedEvents)));

            allEventsBolus = zeros(size(allEventsTime));
            allEventsBolus(any(allEventsTime == data.time(data.bolus > 0 & ~isnan(data.cgm))', 2)) = data.bolus(data.bolus > 0 & ~isnan(data.cgm));
            allEventsBolus = sum(groupedEvents.*allEventsBolus(:));

            allEventsCarb = zeros(size(allEventsTime));
            allEventsCarb(any(allEventsTime == data.time(data.carbs > 0 & ~isnan(data.cgm))', 2)) = data.carbs(data.carbs > 0 & ~isnan(data.cgm));
            allEventsCarb = sum(groupedEvents.*allEventsCarb(:));

            allEventsGlucose = data.cgm(allEventsIdx);
            allEventsGlucose = sum(groupedEvents.*allEventsGlucose(:))./sum(groupedEvents);

            allEventsIOB = data.iobBolus(allEventsIdx);
            allEventsIOB = sum(groupedEvents.*allEventsIOB(:))./sum(groupedEvents);

            mealBolusIdx = allEventsIdx(allEventsCarb > 0 & allEventsBolus > 0);
            bolusVal = allEventsBolus(allEventsCarb > 0 & allEventsBolus > 0);
            glucoseVal = allEventsGlucose(allEventsCarb > 0 & allEventsBolus > 0);
            iobBolusVal = allEventsIOB(allEventsCarb > 0 & allEventsBolus > 0);
            dummyCF = 1800/data.TDIEst;
            mealBolusVal = max(bolusVal - max((glucoseVal - 110)/dummyCF - iobBolusVal, 0), 0);

            data.mealBolus(mealBolusIdx) = round(mealBolusVal/0.5)*0.5;
        end
    end
end
end

