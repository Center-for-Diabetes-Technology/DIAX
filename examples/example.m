clc,
clear,
close all,
addpath('../utils/matlab/'),

%% Load data
subj = DIAX('example.json');
subj.toJSON()
subj.plot();
