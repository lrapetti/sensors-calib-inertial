function checkAccelerometersAnysotropy(...
    data_bc,data_ac,sensorsIdxListFile,...
    sensMeasCell_bc,sensMeasCell_ac,...
    figuresHandler)

% measurements before and after calibration
[data.bc,data.ac] = deal(data_bc,data_ac);
[sensMeasCell.bc,sensMeasCell.ac] = deal(sensMeasCell_bc,sensMeasCell_ac);

% number of measurement samples
subSamplingSize = length(sensMeasCell.ac{1,1});

% select accelerometers to check and plot
accIter = 1:length(sensorsIdxListFile);

%% Check distance to 9.807 sphere manifold
%

% Common result buckets
dOrientList = cell(1,length(sensorsIdxListFile));
dOrientListBC = cell(1,length(sensorsIdxListFile));
dOrientListAC = cell(1,length(sensorsIdxListFile));

for acc_i = accIter
    %% distance to a sphere (R=9.807) centered on 0, before calibration
    [~,~,dOrient.bc,~] = SensorDiagnosis.ellipsoid_proj_distance_fromExp(...
        sensMeasCell.bc{1,acc_i}(:,1),...
        sensMeasCell.bc{1,acc_i}(:,2),...
        sensMeasCell.bc{1,acc_i}(:,3),...
        [0 0 0]',[9.807 9.807 9.807]',eye(3,3));
    
    %% distance to a sphere (R=9.807) centered on 0, after calibration
    [~,~,dOrient.ac,~] = SensorDiagnosis.ellipsoid_proj_distance_fromExp(...
        sensMeasCell.ac{1,acc_i}(:,1),...
        sensMeasCell.ac{1,acc_i}(:,2),...
        sensMeasCell.ac{1,acc_i}(:,3),...
        [0 0 0]',[9.807 9.807 9.807]',eye(3,3));
    
    dOrientList{1,acc_i} = dOrient;
    
end

%% Plot figures
%

time = data.ac.tInit + data.ac.parsedParams.time(:);

for acc_i = accIter
    %% Plot distributions
    
    figH = figure(...
        'Name',['calibration of MTB sensor ' data.ac.labels{sensorsIdxListFile(acc_i)}],...
        'WindowStyle', 'docked');
    
    % Add figure to the figure handler
    figLabel = ['figs_' data.ac.labels{sensorsIdxListFile(acc_i)}];
    figuresHandler.addFigure(figH,figLabel);
    
    % If the figure is not docked, use the below command to display it full
    % screen.
    %set(gcf,'PositionMode','manual','Units','normalized','outerposition',[0 0 1 1]);
    
    % distr of signed distances before calibration
    subplot(1,3,1);
    title('distribution of distances to a centered \newline sphere (R=9.807)',...
        'Fontsize',16,'FontWeight','bold');
    [prevh,ditribLogStringBC]=SensorDiagnosis.plotNprintDistrb(dOrientList{1,acc_i}.bc,false,'auto',1);
    [~    ,ditribLogStringAC]=SensorDiagnosis.plotNprintDistrb(dOrientList{1,acc_i}.ac,true,[7/255 100/255 26/255],0.6,prevh);
    
    % Add log string with the distribution parameters to the figure handler
    distribLogLabel = ['distrib_' data.ac.labels{sensorsIdxListFile(acc_i)}];
    figuresHandler.addDistribLog([ditribLogStringBC '\n' ditribLogStringAC],distribLogLabel);
    
    %% Plot norm uniformity improvement
    subplot(1,3,2);
    title('Norm of sensor measurements','Fontsize',16,'FontWeight','bold');
    for iter = 1:subSamplingSize
        normMeas(iter) = norm(sensMeasCell.bc{1,acc_i}(iter,:));
    end
    hold on;
    grid ON;
    normbc = plot(time,normMeas,':b','lineWidth',2.0);
    xlabel('Time (sec)','Fontsize',12);
    ylabel('Acc norm (m/s^2)','Fontsize',12);
    hold off;
    
    for iter = 1:subSamplingSize
        normMeas(iter) = norm(sensMeasCell.ac{1,acc_i}(iter,:));
    end
    hold on;
    grid ON;
    normac = plot(time,normMeas,'r','lineWidth',2.0);
    xlabel('Time (sec)','Fontsize',12);
    ylabel('Acc norm (m/s^2)','Fontsize',12);
    hold off;
    set(gca,'FontSize',12);
    
    legend([normbc,normac],'Before calibration','After calibration')
    %% plot fitting
    subplot(1,3,3);
    title('Projection on ground truth \newline sphere manifold after calibration','Fontsize',16,'FontWeight','bold');
    SensorDiagnosis.plotFittingEllipse([0 0 0]',[9.807 9.807 9.807]',eye(3,3),sensMeasCell.ac{1,acc_i});
end

%% Plot bar graph of all accelerometers distributions before and after calibration

% build matrix of distances
for acc_i = accIter 
    dOrientListBC{1,acc_i} = dOrientList{1,acc_i}.bc;
    dOrientListAC{1,acc_i} = dOrientList{1,acc_i}.ac;
end

dOrientListBC=dOrientListBC(1,accIter);
dOrientListAC=dOrientListAC(1,accIter);
dOrientListBCmat = cell2mat(dOrientListBC);
dOrientListACmat = cell2mat(dOrientListAC);

% Plot
figH = figure(...
    'Name',['calibration of MTB sensor ' ...
    cellArrayOfStr2str(',',data.ac.labels(sensorsIdxListFile(accIter)))],...
    'WindowStyle', 'docked');

% Add figure to the figure handler
figuresHandler.addFigure(figH,'AllDistribBefNaft');

bar([mean(dOrientListBCmat,1)' mean(dOrientListACmat,1)']);

set(gca,'XTick',1:length(sensorsIdxListFile(accIter)),'XTickLabel',data.ac.labels(sensorsIdxListFile(accIter)));
xlabel('MTB board labels','Fontsize',20);
ylabel('distance (m/s^2)','Fontsize',20);
grid on;

hold on;
errorbar((1:length(accIter))-0.15,mean(dOrientListBCmat,1)',...
    std(dOrientListBCmat,0,1)',...
    'r*','lineWidth',2.5);
errorbar((1:length(accIter))+0.15,mean(dOrientListACmat,1)',...
    std(dOrientListACmat,0,1)',...
    'b*','lineWidth',2.5);
hold off

legend('mean before calibration','mean after calibration',...
    '\sigma before calibration','\sigma after calibration');

end


