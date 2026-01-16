function ax1 = generateSummary(obj, ax1)

ax1.Tag = 'summary';
hold(ax1, 'on');
ax1.XLim = [0, 1];
ax1.YLim = [0, 1];
ax1.XAxis.Visible = 'off';
ax1.YAxis.Visible = 'off';
ax1.Color = 'none';

rectangle(ax1, 'Position', [0.0, 0.0, 1.0, 1.0], 'EdgeColor', [0.5, 0.5, 0.5], 'LineWidth', 1.5, 'FaceColor', [0.97, 0.97, 0.97]);

linesNbr = 24;
spacerNbr = 7;
lineWidth = 0.02;
marginY = 0.03;
marginX = 0.03;
lineSpacing = (1 - 2 * marginY - (linesNbr - 1) * lineWidth) / (linesNbr + spacerNbr);
linePos = @(l, s)(1 - l * lineWidth - (l + s - 1) * lineSpacing - marginY);
posX = 0.6;

line = 0;
spacer = 0;
line = line + 1;
plot(ax1, [marginX, marginX + 0.22], [linePos(line, spacer), linePos(line, spacer)]-0.04, 'color', [0.5, 0.5, 0.5], 'LineWidth', 1.5);
text(ax1, marginX, linePos(line, spacer), 'Summary', 'Color', 'k', 'FontSize', 14, 'FontWeight', 'bold');

spacer = spacer + 1;

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Time >250 (%):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getTimeIn(250 + 0.5, inf)), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Time >180 (%):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getTimeIn(180 + 0.5, inf)), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Time In Range (%):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getTimeIn(70, 180 + 0.5)), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Time <70 (%):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getTimeIn(0, 70)), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');
line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Time <54 (%):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getTimeIn(0, 54)), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

spacer = spacer + 1;

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Night In Range (%):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getTimeIn(70, 180 + 1e-2, [0, 6]*60)), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Night In Hypo (%):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getTimeIn(0, 70, [0, 6]*60)), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Night In Hyper (%):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getTimeIn(180 + 1e-2, inf, [0, 6]*60)), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

spacer = spacer + 1;

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Mean Glucose (mg/dl):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getGMean()), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'SD Glucose (mg/dl):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getGlucoseSD()), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'CV Glucose (%):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getGlucoseCV()), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

spacer = spacer + 1;

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'GMI (%):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getGMI()), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Low BG Index:', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getLBGI()), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'High BG Index:', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getHBGI()), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

spacer = spacer + 1;

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Daily Total Insulin (U):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getTotalInsulin()/days(obj.duration)), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Daily Basal Insulin (U):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getTotalBasal()/days(obj.duration)), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Daily Bolus Insulin (U):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getTotalBolus()/days(obj.duration)), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax1, marginX, linePos(line, spacer), '#Bolus per day:', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getNumberOfBolus()/days(obj.duration)), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

spacer = spacer + 1;

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Daily Carbs Consumed (g):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.0f', obj.getDailyCarbActual()), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Daily Carbs Counted (g):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.0f', obj.getDailyCarb()), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

line = line + 1;
text(ax1, marginX, linePos(line, spacer), 'Daily Treats (g):', 'Color', 'k', 'FontSize', 12, 'FontWeight', 'bold');
text(ax1, (1.0 + marginX + posX)/2, linePos(line, spacer), sprintf('%4.2f', obj.getDailyTreat()), 'Color', 'k', 'FontSize', 12, 'HorizontalAlignment', 'center');

spacer = spacer + 1;
