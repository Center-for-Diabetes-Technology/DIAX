function outcomes = computeOutcomes(subjGrp, varargin)
if ~iscell(subjGrp)
    subjGrp = {subjGrp};
end

names = cellfun(@(c)(strcat('subj', num2str(c))), num2cell(1:numel(subjGrp)), 'UniformOutput', false);
saveFolder = '';
useBG = false;
freqInDays = 7;
durationInDays = NaN;
fields = {'GMI', 'Smbg', 'SmbgCV', 'TIR', 'Insulin', 'SmbgHypo2', 'SmbgHypo1', 'TBR1'};
for nVar = 1:2:length(varargin)
    switch lower(varargin{nVar})
        case {'name', 'names', 'legend', 'arms'}
            names = varargin{nVar+1};
        case {'bg', 'usebg'}
            useBG = varargin{nVar+1};
        case {'frequency', 'freqindays', 'freq'}
            freqInDays = varargin{nVar+1};
        case {'duration', 'durationindays', 'durr'}
            durationInDays = varargin{nVar+1};
        case 'fields'
            fields = varargin{nVar+1};
        case {'save', 'savefolder', 'folder'}
            saveFolder = varargin{nVar+1};
    end
end

if isnan(durationInDays)
    durationInDays = freqInDays;
end

overallDuration = days(subjGrp{1}(1).duration);
nSubjects = numel(subjGrp{1});

outcomes = {};
outcomesIdxToRun = numel(subjGrp):-1:1;
if ~isempty(saveFolder)
    armsLoaded = 0;
    for gr = numel(subjGrp):-1:1
        if useBG
            fileName = sprintf('%s/%s/BGoutcomes_n%d_days%d_freq%d_durr%d.xlsx', saveFolder, names{gr}, nSubjects, overallDuration, freqInDays, durationInDays);
        else
            fileName = sprintf('%s/%s/outcomes_n%d_days%d_freq%d_durr%d.xlsx', saveFolder, names{gr}, nSubjects, overallDuration, freqInDays, durationInDays);
        end
        if exist(fileName, 'file') == 2
            armsLoaded = armsLoaded + 1;
            SheetNames = sheetnames(fileName);
            for fn = SheetNames(:)'
                tab_ = readtable(fileName, 'Sheet',fn{1});
                outcomes{gr}.(fn{1}) = tab_{:, :};
            end
            outcomesIdxToRun(outcomesIdxToRun == gr) = [];
        end
    end
    if armsLoaded == numel(subjGrp) || isempty(outcomesIdxToRun)
        return;
    end
end

for gr = outcomesIdxToRun
    obj = subjGrp{gr}.copy();
    nPop = numel(obj);

    obj.setUseBG(useBG);
    chunks = obj.getChunks(freqInDays, durationInDays);

    nTot = numel(chunks);
    if length(freqInDays) > 1
        outcomes{gr}.time = cumsum(freqInDays)';
    else
        outcomes{gr}.time = (freqInDays:freqInDays:freqInDays*nTot)';
    end

    % SMBG Fasting Mean
    if any(strcmp(fields, 'SmbgFasting'))
        outcomes{gr}.SmbgFasting = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.SmbgFasting(k, :) = [chunks{k}.getSMBGFastingMean()];
        end
    end

    % SMBG Fasting SD
    if any(strcmp(fields, 'SmbgFastingSD'))
        outcomes{gr}.SmbgFastingSD = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.SmbgFastingSD(k, :) = [chunks{k}.getSMBGFastingSD()];
        end
    end

    % SMBG Fasting CV
    if any(strcmp(fields, 'SmbgFastingCV'))
        outcomes{gr}.SmbgFastingCV = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.SmbgFastingCV(k, :) = [chunks{k}.getSMBGFastingCV()];
        end
    end

    % SMBG Mean
    if any(strcmp(fields, 'Smbg'))
        outcomes{gr}.Smbg = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.Smbg(k, :) = [chunks{k}.getSMBGMean()];
        end
    end

    % SMBG SD
    if any(strcmp(fields, 'SmbgSD'))
        outcomes{gr}.SmbgSD = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.SmbgSD(k, :) = [chunks{k}.getSMBGSD()];
        end
    end

    % SMBG CV
    if any(strcmp(fields, 'SmbgCV'))
        outcomes{gr}.SmbgCV = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.SmbgCV(k, :) = [chunks{k}.getSMBGCV()];
        end
    end

    % SMBG hypos level 1
    if any(strcmp(fields, 'SmbgHypo1'))
        outcomes{gr}.SmbgHypo1 = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.SmbgHypo1(k, :) = [chunks{k}.getSMBGLess(70)];
        end
    end

    % SMBG hypos level 2
    if any(strcmp(fields, 'SmbgHypo2'))
        outcomes{gr}.SmbgHypo2 = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.SmbgHypo2(k, :) = [chunks{k}.getSMBGLess(54)];
        end
    end

    % Treats hypos level 1
    if any(strcmp(fields, 'TreatHypo1'))
        outcomes{gr}.TreatHypo1 = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.TreatHypo1(k, :) = [chunks{k}.getTreatsAmount(15)];
        end
    end

    % Treats hypos level 2
    if any(strcmp(fields, 'TreatHypo2'))
        outcomes{gr}.TreatHypo2 = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.TreatHypo2(k, :) = [chunks{k}.getTreatsAmount(30)];
        end
    end

    % CGM hypos level 1
    if any(strcmp(fields, 'CGMHypo1'))
        outcomes{gr}.CGMHypo1 = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.CGMHypo1(k, :) = [chunks{k}.getCGMHypoLvl1()];
        end
    end

    % CGM hypos level 2
    if any(strcmp(fields, 'CGMHypo2'))
        outcomes{gr}.CGMHypo2 = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.CGMHypo2(k, :) = [chunks{k}.getCGMHypoLvl2()];
        end
    end

    % GMI
    if any(strcmp(fields, 'GMI'))
        outcomes{gr}.GMI = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.GMI(k, :) = [chunks{k}.getGMI()];
        end
    end

    % Glucose Mean
    if any(strcmp(fields, 'GMean'))
        outcomes{gr}.GMean = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.GMean(k, :) = [chunks{k}.getGMean()];
        end
    end

    % Glucose SD
    if any(strcmp(fields, 'GSD'))
        outcomes{gr}.GSD = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.GSD(k, :) = [chunks{k}.getGlucoseSD()];
        end
    end

    % Glucose CV
    if any(strcmp(fields, 'GCV'))
        outcomes{gr}.GCV = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.GCV(k, :) = [chunks{k}.getGlucoseCV()];
        end
    end

    % TIR
    if any(strcmp(fields, 'TIR'))
        outcomes{gr}.TIR = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.TIR(k, :) = [chunks{k}.getTimeIn(70, 180.5)];
        end
    end

    % TAR1
    if any(strcmp(fields, 'TAR1'))
        outcomes{gr}.TAR1 = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.TAR1(k, :) = [chunks{k}.getTimeIn(180.5, inf)];
        end
    end

    % TAR2
    if any(strcmp(fields, 'TAR2'))
        outcomes{gr}.TAR2 = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.TAR2(k, :) = [chunks{k}.getTimeIn(250.5, inf)];
        end
    end

    % TBR1
    if any(strcmp(fields, 'TBR1'))
        outcomes{gr}.TBR1 = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.TBR1(k, :) = [chunks{k}.getTimeIn(0, 70)];
        end
    end

    % TBR2
    if any(strcmp(fields, 'TBR2'))
        outcomes{gr}.TBR2 = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.TBR2(k, :) = [chunks{k}.getTimeIn(0, 54)];
        end
    end

    % Basal
    if any(strcmp(fields, 'Basal'))
        outcomes{gr}.Basal = nan(nTot, nPop);
        for k = nTot:-1:1
            if length(freqInDays) > 1
                outcomes{gr}.Basal(k, :) = [chunks{k}.getTotalBasal()/freqInDays(k)];
            else
                outcomes{gr}.Basal(k, :) = [chunks{k}.getTotalBasal()/freqInDays];
            end
        end
    end

    % BasalDaily
    if any(strcmp(fields, 'BasalDaily'))
        outcomes{gr}.BasalDaily = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.BasalDaily(k, :) = [chunks{k}.getDailyBasal()];
        end
    end

    % Bolus
    if any(strcmp(fields, 'Bolus'))
        outcomes{gr}.Bolus = nan(nTot, nPop);
        for k = nTot:-1:1
            if length(freqInDays) > 1
                outcomes{gr}.Bolus(k, :) = [chunks{k}.getTotalBolus()/freqInDays(k)];
            else
                outcomes{gr}.Bolus(k, :) = [chunks{k}.getTotalBolus()/freqInDays];
            end
        end
    end

    % BolusDaily
    if any(strcmp(fields, 'BolusDaily'))
        outcomes{gr}.BolusDaily = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.BolusDaily(k, :) = [chunks{k}.getDailyBolus()];
        end
    end

    % Insulin
    if any(strcmp(fields, 'Insulin'))
        outcomes{gr}.Insulin = nan(nTot, nPop);
        for k = nTot:-1:1
            if length(freqInDays) > 1
                outcomes{gr}.Insulin(k, :) = [chunks{k}.getTotalInsulin()/freqInDays(k)];
            else
                outcomes{gr}.Insulin(k, :) = [chunks{k}.getTotalInsulin()/freqInDays];
            end
        end
    end

    % Basal/Bolus Ratio
    if any(strcmp(fields, 'BasalBolusRatio'))
        outcomes{gr}.BasalBolusRatio = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.BasalBolusRatio(k, :) = chunks{k}.getTotalBasal()./chunks{k}.getTotalBolus();
        end
    end

    % Carbs
    if any(strcmp(fields, 'Carbs'))
        outcomes{gr}.Carbs = nan(nTot, nPop);
        for k = nTot:-1:1
            if length(freqInDays) > 1
                outcomes{gr}.Carbs(k, :) = [chunks{k}.getTotalCarb()/freqInDays(k)];
            else
                outcomes{gr}.Carbs(k, :) = [chunks{k}.getTotalCarb()/freqInDays];
            end
        end
    end

    % LBGI
    if any(strcmp(fields, 'LBGI'))
        outcomes{gr}.LBGI = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.LBGI(k, :) = [chunks{k}.getLBGI()];
        end
    end

    % HBGI
    if any(strcmp(fields, 'HBGI'))
        outcomes{gr}.HBGI = nan(nTot, nPop);
        for k = nTot:-1:1
            outcomes{gr}.HBGI(k, :) = [chunks{k}.getHBGI()];
        end
    end

    if ~isempty(saveFolder)
        for gr = numel(subjGrp):-1:1
            if useBG
                fileName = sprintf('%s/%s/BGoutcomes_n%d_days%d_freq%d_durr%d.xlsx', saveFolder, names{gr}, nSubjects, overallDuration, freqInDays, durationInDays);
            else
                fileName = sprintf('%s/%s/outcomes_n%d_days%d_freq%d_durr%d.xlsx', saveFolder, names{gr}, nSubjects, overallDuration, freqInDays, durationInDays);
            end
            Subject.ensureFolder(fileName);
            for fn = fieldnames(outcomes{gr})'
                writematrix(outcomes{gr}.(fn{1}), fileName, 'Sheet', fn{1});
            end
        end
    end
end