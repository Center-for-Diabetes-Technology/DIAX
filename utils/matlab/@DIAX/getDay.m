function out = getDay(obj, dayNo, offset, times, firstDay)
if nargin < 5
    firstDay = [];
end
if nargin < 4
    times = {};
end
if nargin < 3
    offset = [0.0, 0.0];
end

if isscalar(offset)
    offset = [offset(1) offset(1)];
end

if numel(obj) > 1
    out = arrayfun(@(c)(c.getDay(dayNo, offset)), obj, 'UniformOutput', false);
    if ~iscell(dayNo)
        out = [out{:}];
    end
    return;
end

if iscell(dayNo)
    for fn = obj.timeSeriesFields
        if isempty(obj.(fn{1}))
            continue;
        end
        times.(fn{1}) = datenum(obj.(fn{1}).time);
    end
    firstDay = datenum(dateshift(obj.startDate, 'start', 'day'));
    out = cellfun(@(c)(obj.getDay(c, offset, times, firstDay)), dayNo);
    return;
end

if ischar(dayNo)
    dayNo = datetime(dayNo);
end

if isdatetime(dayNo)
    dayNo = floor(days(dayNo - dateshift(obj.startDate, 'start', 'day'))) + 1;
end

if dayNo <= 0
    lastDayIdx = floor(days(obj.endDate - dateshift(obj.startDate, 'start', 'day'))) + 1;
    dayNo = lastDayIdx + dayNo;
end

if isempty(firstDay)
    firstDay = datenum(dateshift(obj.startDate, 'start', 'day'));
end
if isdatetime(dayNo)
    dayNo = floor(days(dayNo - datetime(firstDay, 'ConvertFrom', 'datenum'))) + 1;
end

out = obj.copy();
if length(dayNo) > 1
    out.name = [out.name, sprintf('_%02d-%02d', dayNo(1), dayNo(end))];
else
    out.name = [out.name, sprintf('#%02d', dayNo)];
end

useOptimizedCode = false;
if all(diff(dayNo) == 1) 
    useOptimizedCode = true;
end

if ~isempty(times)
    fields_ = fieldnames(times)';
else
    fields_ = obj.timeSeriesFields;
end

for fn = fields_
    if isempty(times) && isempty(obj.(fn{1}))
        continue;
    end

    if ~isempty(times)
        time = times.(fn{1});
    else
        time = datenum(obj.(fn{1}).time);
    end
    if useOptimizedCode
        idx = (time - firstDay) >= dayNo(1) - 1 & (time - firstDay) < dayNo(end);
    else
        idx = false(size(time));
        for d = dayNo(:)'
            idx = idx | ((time - firstDay) > d - 1 + offset(1) - 0.1/1440 & (time - firstDay) < d + offset(2) - 0.1/1440);
        end
    end
    if offset(1) < 0
        idx = idx | ((time - firstDay) >= dayNo(1) + offset(1) - 1 & (time - firstDay) < dayNo(1) - 1);
    else
        idx((time - firstDay) < dayNo(1) - 1 + offset(1)) = false;
    end
    if offset(2) > 0
        idx = idx | ((time - firstDay) >= dayNo(end) & (time - firstDay) < dayNo(end) + offset(2));
    else
        idx((time - firstDay) >= dayNo(end) + offset(2)) = false;
    end

    out.(fn{1}) = out.(fn{1})(idx, :);

    if strcmp(fn{1}, 'basalRate')
        % copy last value for basalRate
        if ~isempty(out.basalRate) && ~isempty(out.cgm) && out.basalRate.time(1) > out.cgm.time(1)
            lastIdx = find(idx);
            lastIdx = lastIdx(1) - 1;
            if lastIdx > 0
                out.basalRate = [timetable(out.cgm.time(1), obj.basalRate.value(lastIdx), 'VariableNames', {'value'}); out.basalRate];
            end
        end
    end
end

end
