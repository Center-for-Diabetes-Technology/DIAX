clc,
clear,
close all,
addpath('../utils/matlab/'),

%% Data Folder
dataFolder = '../../diax/DCLP3/';

%% Load data
listings = dir([dataFolder, '/*.json']);
subjs = DIAX([listings(1).folder, filesep, listings(1).name]);
jsonData = subjs.toJSON();
