function loadData(obj)
%LOADDATA Summary of this function goes here
%   Detailed explanation goes here

% define filter
switch obj.filtParams.type
    case 'sgolay'
        filt = @sgolayfilt;
        filtParams = {obj.filtParams.sgolayK,obj.filtParams.sgolayF};
    case 'none'
        filt = @(x) x;
        filtParams = {};
    otherwise
        error('Unknown filter type !!');
end

% length(obj.parts) is the lists (parts, labels, ndof) length in 'data'
% structure. list length = number of sensors (ex: 11 acc + "leg_position").
% For instance, for the leg, q_1 to q_6 are seen like a single sensor of 6
% dof ("leg_position"), and that's the way it is read from stateExt:o.

% Create function handles for assigning variables :
%   q_<labels{i}>, dq_<labels{i}>, d2q_<labels{i}>
%   qs_<labels{i}>, dqs_<labels{i}>, d2qs_<labels{i}>
%   qsRad_<labels{i}>, dqsRad_<labels{i}>, d2qsRad_<labels{i}>
%   y_<labels{i}>
%   ys_<labels{i}>

% meas = {};
% 
% for i = 1 : length(obj.parts)
%     
%     eval(['meas{i}.t = @(x) obj.t_' obj.labels{i} ' = x;']);
%     
%     if strcmp(obj.type{i}, 'stateExt:o');
%         eval(['meas{i}.q = @(x) obj.q_' obj.labels{i} ' = x;']);
%         eval(['meas{i}.dq = @(x) obj.dq_' obj.labels{i} ' = x;']);
%         eval(['meas{i}.d2q = @(x) obj.d2q_' obj.labels{i} ' = x;']);
% 
%         eval(['meas{i}.qs = @(x) obj.qs_' obj.labels{i} ' = x;']);
%         eval(['meas{i}.dqs = @(x) obj.dqs_' obj.labels{i} ' = x;']);
%         eval(['meas{i}.d2qs = @(x) obj.d2qs_' obj.labels{i} ' = x;']);
% 
%         eval(['meas{i}.qsRad = @(x) obj.qsRad_' obj.labels{i} ' = x;']);
%         eval(['meas{i}.dqsRad = @(x) obj.dqsRad_' obj.labels{i} ' = x;']);
%         eval(['meas{i}.d2qsRad = @(x) obj.d2qsRad_' obj.labels{i} ' = x;']);
%    else
%         eval(['meas{i}.y = @(x) obj.y_' obj.labels{i} ' = x;']);
%         eval(['meas{i}.ys = @(x) obj.ys_' obj.labels{i} ' = x;']);
%    end
% end

% init buffers
qBuff = []; dqBuff = []; d2qBuff = []; dqMBuff = []; tauBuff = []; pwmBuff = []; currBuff = []; tStateBuff = [];
for i = 1 : length(obj.parts)
    bufferId = ['buffer_' obj.parts{i} '_' obj.type{i}(1:end-2)];
    eval(['readFile_' bufferId ' = []']);
end

% Load data from dump files
for i = 1 : length(obj.parts)
    file = [obj.path '/' obj.parts{i} '/' obj.type{i} '/data.log'];
    % this buffer Id avoids reading the same file twice
    bufferId = ['buffer_' obj.parts{i} '_' obj.type{i}(1:end-2)];
    
    % select sensor data parser
    switch obj.type{i}
        case 'inertialMTB'
            initParser = @(dataBuffer) obj.parseMTBdata(dataBuffer);
            getSensorDataPosition = @(sensorLabel) obj.mapMTBlabel2position(sensorLabel);
        case 'inertial'
            initParser = @(dataBuffer) obj.parseIMUdata(dataBuffer);
            getSensorDataPosition = @(sensorLabel) obj.mapIMUlabel2position(sensorLabel);
        otherwise
    end
    
    % read the file and parse the data
    switch obj.type{i}
        case 'stateExt:o'
            q    = ['q_' obj.labels{i}];
            dq   = ['dq_' obj.labels{i}];
            d2q  = ['d2q_' obj.labels{i}];
            dqM  = ['dqM_' obj.labels{i}];
            tau  = ['tau_' obj.labels{i}];
            pwm  = ['pwm_' obj.labels{i}];
            curr = ['curr_' obj.labels{i}];
            t    = ['time_' obj.labels{i}];
            % trigger and register the unique read of the file
            eval(['readFile_' bufferId ' = isempty(readFile_' bufferId ');']);
            eval(['readFile = readFile_' bufferId]);
            % Read file.
            if readFile
                [qBuff,dqBuff,d2qBuff,dqMBuff,tauBuff,pwmBuff,currBuff,tStateBuff] = readStateExt(obj.ndof{i},file);
                qBuff = qBuff + obj.calib{i};
            end
            % Parse file content.
            % (dynamicaly create new fields of "data")
            eval(['obj.parsedParams.' t ' = tStateBuff;']);
            eval(['obj.parsedParams.'  q  '= qBuff(' mat2str(obj.index{i}) ',:);']);
            eval(['obj.parsedParams.' dq  '= dqBuff(' mat2str(obj.index{i}) ',:);']);
            eval(['obj.parsedParams.' d2q '= d2qBuff(' mat2str(obj.index{i}) ',:);']);
            eval(['obj.parsedParams.' dqM '= dqMBuff(' mat2str(obj.index{i}) ',:);']);
            eval(['obj.parsedParams.' tau '= tauBuff(' mat2str(obj.index{i}) ',:);']);
            eval(['obj.parsedParams.' pwm '= pwmBuff(' mat2str(obj.index{i}) ',:);']);
            eval(['obj.parsedParams.' curr '= currBuff(' mat2str(obj.index{i}) ',:);']);
            
            if obj.diff_q
                eval(['obj.parsedParams.'   q '(:, :   )= filt(obj.parsedParams.'   q ''',filtParams{:})'' ;'])
                eval(['obj.parsedParams.'  dq '(:,2:end)= 1/mean(diff(obj.parsedParams.' t ')).*diff(obj.parsedParams.'  q ''')'' ;'])
                eval(['obj.parsedParams.'   dq '(:, :   )= filt(obj.parsedParams.'   dq ''',filtParams{:})'' ;'])
                eval(['obj.parsedParams.' d2q '(:,2:end)= 1/mean(diff(obj.parsedParams.' t ')).*diff(obj.parsedParams.' dq ''')'' ;'])
            end
            
        case {'inertialMTB','inertial'}
            y    = ['y_' obj.labels{i}];
            t    = ['time_' obj.labels{i}];
            % trigger and register the unique read of the file
            eval(['readFile_' bufferId ' = isempty(readFile_' bufferId ');']);
            eval(['readFile = readFile_' bufferId]);
            % Read file.
            if readFile
                % extract time and MTB sensor data
                [yBuff,tAccBuff] = readDataDumper(file);
                % parse the MTB sensor metadata and build the sensor mapping
                initParser(yBuff);
            end
            % Parse file content.
            fprintf('Loaded sensor %s\n',obj.labels{i})
            eval(['obj.parsedParams.' t ' = tAccBuff;']);
            % retrieve the correct offsets to index 'yBuff[]'. The offsets are retrieved
            % using the sensor mapping built from the metadata parsing.
            eval(['obj.parsedParams.' y '= yBuff(:,' getSensorDataPosition(obj.labels{i}) ');']);
            
            if(strcmp(y(end-2:end), 'imu') && obj.diff_imu)
                eval(['obj.parsedParams.' y '(2:end,4:6)= 1/mean(diff(obj.parsedParams.' t ')).*diff(filt(obj.parsedParams.' y '(:,4:6),filtParams{:}));'])
            end
            eval(['obj.parsedParams.' t ' = obj.parsedParams.' t ''';']);
            eval(['obj.parsedParams.' y '= obj.parsedParams.' y ''';']);
            
            % add filtering
            eval(['obj.parsedParams.' y '=filt(obj.parsedParams.' y ''',filtParams{:})'';']);
            
    end
end

min_times = [];
max_times = [];
for i = 1 : length(obj.labels)
   max_time  = ['max_time_', obj.labels{i}];
   min_time  = ['min_time_', obj.labels{i}];
   t         = ['obj.parsedParams.time_' obj.labels{i}];
   eval([max_time ' = max(' t ');']);
   eval([min_time ' = min(' t ');']);
   
   min_times = [min_times eval(min_time)];
   max_times = [max_times eval(max_time)];
end

time_i = max(min_times);
time_f = min(max_times);

for i = 1 : length(obj.labels)
   tf  = eval(['max_time_', obj.labels{i}]);
   ti  = eval(['min_time_', obj.labels{i}]);
   
   if abs(tf - time_f) > 1 || abs(ti - time_i) > 1
      fprintf(['[WARNING] There is some lag in the ' obj.parts{i} ' data: %f, %f\n'], abs(tf - time_f) ,abs(ti - time_i))
   end
   
end

% if we specified an invalid tEnd, overwrite it with the end time from data log
if obj.tEnd == -1
    obj.tEnd = time_f - time_i;
end

time   = linspace(time_i+obj.tInit, time_i+obj.tEnd, obj.nSamples);

%%

dtime   = time(1);
for i = 1 : length(obj.parts)
   
   if strcmp(obj.type{i}, 'stateExt:o')
      q    = ['obj.parsedParams.q_' obj.labels{i}];
      dq   = ['obj.parsedParams.dq_' obj.labels{i}];
      d2q  = ['obj.parsedParams.d2q_' obj.labels{i}];
      dqM  = ['obj.parsedParams.dqM_' obj.labels{i}];
      tau  = ['obj.parsedParams.tau_' obj.labels{i}];
      pwm  = ['obj.parsedParams.pwm_' obj.labels{i}];
      curr = ['obj.parsedParams.curr_' obj.labels{i}];
      t    = ['obj.parsedParams.time_' obj.labels{i}];
      
      qs    = ['qs_' obj.labels{i}];
      dqs   = ['dqs_' obj.labels{i}];
      d2qs  = ['d2qs_' obj.labels{i}];
      dqMs  = ['dqMs_' obj.labels{i}];
      taus  = ['taus_' obj.labels{i}];
      pwms  = ['pwms_' obj.labels{i}];
      currs = ['currs_' obj.labels{i}];
      
      % [qs_la, dqs_la, d2qs_la] = resampleState(time, time_la, q_la, dq_la, d2q_la);
      eval(['[obj.parsedParams.' qs ', obj.parsedParams.' dqs ', obj.parsedParams.' d2qs ', obj.parsedParams.' dqMs ', obj.parsedParams.' taus ', obj.parsedParams.' pwms ', obj.parsedParams.' currs '] = resampleState(time,' t ',' q ',' dq ',' d2q ',' dqM ',' tau ',' pwm ',' curr ');']);
   else
      y    = ['obj.parsedParams.y_'  obj.labels{i}];
      t    = ['obj.parsedParams.time_' obj.labels{i}];
      ys   = ['ys_' obj.labels{i}];
      eval(['obj.parsedParams.' ys ' = interp1(' t ',' y ''', time)'';']);
   end
   % time_h  = time_h  - dtime;
   eval([t '=' t '- dtime;']);
end
obj.parsedParams.time = time    - dtime;

for i = 1 : length(obj.parts)
   if obj.visualize{i} && strcmp(obj.type{i}, 'stateExt:o')
      q    = ['obj.parsedParams.q_' obj.labels{i}];
      dq   = ['obj.parsedParams.dq_' obj.labels{i}];
      d2q  = ['obj.parsedParams.d2q_' obj.labels{i}];
      t    = ['obj.parsedParams.time_' obj.labels{i}];
      
      qs   = ['qs_' obj.labels{i}];
      dqs  = ['dqs_' obj.labels{i}];
      d2qs = ['d2qs_' obj.labels{i}];
      
      figure
      subplot(311)
      eval(['plot(' t ',' q ')'])
      hold on
      eval(['plot(obj.time,obj.parsedParams.' qs ', ''--'' )' ]);
      title([' q_{' obj.labels{i} '}'])
      subplot(312)
      eval(['plot(' t ',' dq ')'])
      hold on
      eval(['plot(obj.time,obj.parsedParams.' dqs ', ''--'' )' ]);
      title(['dq_{' obj.labels{i} '}'])
      subplot(313)
      eval(['plot(' t ',' d2q ')'])
      hold on
      eval(['plot(obj.time,obj.parsedParams.' d2qs ', ''--'' )' ]);
      title(['d2q_{' obj.labels{i} '}'])
   elseif obj.visualize{i}
      y    = ['obj.parsedParams.y_'  obj.labels{i}];
      t    = ['obj.parsedParams.time_' obj.labels{i}];
      ys   = ['ys_' obj.labels{i}];
      
      figure
      J = obj.ndof{i};
      for j = 1 : J/3
         subplot([num2str(J/3) '1' num2str(j)])
         I = 1+(j-1)*3 : 3*j;
         eval(['plot(' t ',' y '(I,:))'])
         hold on
         eval(['plot(obj.time,obj.parsedParams.' ys '(I,:), ''--'' )' ]);
         title(['y_{' obj.labels{i} '}'])
      end
   end
end


%% Process raw sensor data
deg_to_rad = pi/180.0;
gyro_gain = deg_to_rad*7.6274e-03;
for i = 1 : length(obj.parts)
    % gain for the processed sensor
    % acc_gain must be applied before the calibration matrix
    % since the calibration procedure is done after acc_gain
    % is set.
    if ~strcmp(obj.type{i}, 'stateExt:o')
        acc_gain = obj.calib{i}.gain;
        centre = obj.calib{i}.centre;
        C = obj.calib{i}.C;
    end

    % convert raw data
    t    = ['time_' obj.labels{i}];
    ys   = ['ys_' obj.labels{i}];
    if( strcmp(obj.labels{i},'lh_imu') || ...
            strcmp(obj.labels{i},'rh_imu') )
        eval(['obj.parsedParams.' ys '(1:3,:) = ' ...
            'C*(obj.parsedParams.' ys '(1:3,:)*acc_gain-repmat(centre,1,nbSamples));']);
        eval(['obj.parsedParams.' ys '(4:6,:) = ' ...
            'gyro_gain*obj.parsedParams.' ys '(4:6,:);']);
    end
    if( strcmp(obj.labels{i},'imu') )
        eval(['obj.parsedParams.' ys '(4:6,:) = ' ...
            'deg_to_rad*obj.parsedParams.' ys '(4:6,:);']);
    end
    if( ~isempty(regexp(obj.labels{i},'mtb_acc|ems_acc|imu_acc','match')) )
        eval(['nbSamples = size(obj.parsedParams.' ys '(1:3,:),2);']);
        eval(['obj.parsedParams.' ys '(1:3,:) = ' ...
            'C*(obj.parsedParams.' ys '(1:3,:)*acc_gain-repmat(centre,1,nbSamples));']);        
    end
end

fprintf('Processed raw sensors\n')


%%
% Convert qs_xxx, dqs_xxx, d2qs_xxx variables from degrees to radians
%
% % Convert qs_xxx, dqs_xxx, d2qs_xxx variables from degrees to radians
% for i = 1 : length(obj.parts)
%     if strcmp(obj.type{i}, 'stateExt:o');
%         meas{i}.qsRad([obj.qs_rleg].*pi/180);
%         meas{i}.dqsRad([obj.dqs_rleg].*pi/180);
%         meas{i}.d2qsRad([obj.d2qs_rleg].*pi/180);
%     end
% end
%
% obj.q - meas{12}.qsRad_rleg
% obj.dq - meas{12}.dqsRad_rleg
% obj.d2q - meas{12}.d2qsRad_rleg


for i = 1 : length(obj.parts)
    if strcmp(obj.type{i}, 'stateExt:o')
        q    = ['q_' obj.labels{i}];
        dq   = ['dq_' obj.labels{i}];
        d2q  = ['d2q_' obj.labels{i}];
        dqM  = ['dqM_' obj.labels{i}];
        
        qRad    = ['qRad_' obj.labels{i}];
        dqRad   = ['dqRad_' obj.labels{i}];
        d2qRad  = ['d2qRad_' obj.labels{i}];
        dqMRad  = ['dqMRad_' obj.labels{i}];
        
        eval(['obj.parsedParams.' qRad ' = obj.parsedParams.' q '*pi/180;']);
        eval(['obj.parsedParams.' dqRad ' = obj.parsedParams.' dq '*pi/180;']);
        eval(['obj.parsedParams.' d2qRad ' = obj.parsedParams.' d2q '*pi/180;']);
        eval(['obj.parsedParams.' dqMRad ' = obj.parsedParams.' dqM '*pi/180;']);
        
        qs    = ['qs_' obj.labels{i}];
        dqs   = ['dqs_' obj.labels{i}];
        d2qs  = ['d2qs_' obj.labels{i}];
        dqMs  = ['dqMs_' obj.labels{i}];
        
        qsRad    = ['qsRad_' obj.labels{i}];
        dqsRad   = ['dqsRad_' obj.labels{i}];
        d2qsRad  = ['d2qsRad_' obj.labels{i}];
        dqMsRad  = ['dqMsRad_' obj.labels{i}];
        
        eval(['obj.parsedParams.' qsRad ' = obj.parsedParams.' qs '*pi/180;']);
        eval(['obj.parsedParams.' dqsRad ' = obj.parsedParams.' dqs '*pi/180;']);
        eval(['obj.parsedParams.' d2qsRad ' = obj.parsedParams.' d2qs '*pi/180;']);
        eval(['obj.parsedParams.' dqMsRad ' = obj.parsedParams.' dqMs '*pi/180;']);
    end
end



end