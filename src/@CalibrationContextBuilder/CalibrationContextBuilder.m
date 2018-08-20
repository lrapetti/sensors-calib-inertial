classdef CalibrationContextBuilder < handle
    % This class holds :
    % - the robots sensors and joints names definitions as per the robot URDF
    % model
    % - the context for the cost function to be minimised,
    % as the init methods and the a specific cost function.
    % 
    % Detailed explanation goes here
        
    properties (SetAccess = public, GetAccess = public)
        grav_idyn             %% gravity iDynTree object
        dofs                  %% joint information: DOF
        qi_idyn               %% joint position iDynTree object
        dqi_idyn              %% joint velocity iDynTree object
        d2qi_idyn             %% joint acceleration iDynTree object
        estimator             %% estimator for computing the estimated sensor measurements
        base_link_index       %% input param of estimator. iDynTree model indexing
        fullBodyUnknowns      %% input param of estimator
        estMeasurements       %% input param of estimator
        sink1                 %% sink for output estContactForces
        sink2                 %% sink for output estJointTorques
        sensorsIdxListModel = []; %% subset of active sensors: indices from iDynTree model
        sensorsIdxListFile  = []; %% subset of active sensors: indices from 'data.frame' list,
                                  %  ordered as per the data.log format.
        jointsIdxFile             %% index of 'StateExt' in 'data.frame' list
        ctrledJointsIdxFromModel  = []; %% map contolled joints to iDynTree joint index
        calibJointsIdxFromModel = [];   %% map calibrated joints to iDynTree joint index
        estimatedSensorLinAcc     %% predicted measurement on sensor frame
        tmpSensorLinAcc           %% sensor measurement
        q0i     = [];             %% joint positions for the current processed part.
        dqi     = [];             %% joint velocities for the current processed part.
        d2qi    = [];             %% joint accelerations for the current processed part.
        sub_q0i
        sub_dqi
        sub_d2qi
        Dq0;
        DqiEnc  = [];             %% virtual joint offsets from the encoders.
        %% specific to APPROACH 2: measurements projected on each link
        traversal_Lk              %% full traversal for computing the link positions
        fixedBasePos              %% full tree joint positions (including base link)
                                   % (required by the estimator interface,
                                   % but the base position is not really
                                   % relevant for computing the transforms
                                   % between segment frames).
        linkPos                   %% link positions w.r.t. the chosen base (base="projection link")
        segments = {};            %% list of segments for current part.
    end
    
    methods
        function obj = CalibrationContextBuilder(estimator)
            %% Prepare inputs for updating the kinematics information in the estimator
            %
            % Compute the kinematics information necessary for the accelerometer
            % sensor measurements estimation. We assume the robot root link is fixed to
            % the ground (steady kart pole). We then assume to know the gravity (ground
            % truth) projected on the frame (base_link) fixed to the root link. For more
            % info on iCub frames check: http://wiki.icub.org/wiki/ICub_Model_naming_conventions.
            %
            obj.grav_idyn = iDynTree.Vector3();
            grav = [0.0;0.0;-9.81];
            obj.grav_idyn.fromMatlab(grav);
            
            %% Set the estimator and model...
            %
            obj.estimator = estimator;
            
            % Base link index for later applying forward kynematics
            % (specific to APPROACH 1)
            obj.base_link_index = obj.estimator.model.getFrameIndex('base_link');
            
            % Get joint information: DOF
            obj.dofs = obj.estimator.model.getNrOfDOFs();
            
            % create joint position iDynTree objects
            % Note: 'JointPosDoubleArray' is a special type for future evolution which
            % will handle quaternions. But for now the type has the format as
            % 'JointDOFsDoubleArray'.
            obj.qi_idyn   = iDynTree.JointPosDoubleArray(obj.dofs);
            obj.dqi_idyn  = iDynTree.JointDOFsDoubleArray(obj.dofs);
            obj.d2qi_idyn = iDynTree.JointDOFsDoubleArray(obj.dofs);
            
            % Set the position of base link
            obj.fixedBasePos = iDynTree.FreeFloatingPos(obj.estimator.model);
            obj.fixedBasePos.worldBasePos().setRotation(iDynTree.Rotation.Identity());
            obj.fixedBasePos.worldBasePos().setPosition(iDynTree.Position.Zero());

            %% Specify unknown wrenches (unknown Full wrench applied at the origin of the base_link frame)
            % We need to set the location of the unknown wrench. We express the unknown
            % wrench at the origin of the base_link frame (conctact point wrt to base_link is zero)
            unknownWrench = iDynTree.UnknownWrenchContact();
            unknownWrench.unknownType = iDynTree.FULL_WRENCH;
            unknownWrench.contactPoint.zero();
            % 'forceDirection', 'knownWrench' are irrelevant for an unknown FULL_WRENCH.
            % 'contactId' is by default 0.
            
            % The fullBodyUnknowns is a class storing all the unknown external wrenches
            % acting on a class: we consider the pole reaction on the base link as the only
            % external force.
            % Build an empty list.
            obj.fullBodyUnknowns = iDynTree.LinkUnknownWrenchContacts(obj.estimator.model());
            obj.fullBodyUnknowns.clear();
            obj.fullBodyUnknowns.addNewContactInFrame(obj.estimator.model, ...
                                                      obj.base_link_index, ...
                                                      unknownWrench);
            
            % Print the unknowns to make sure that everything is properly working
            obj.fullBodyUnknowns.toString(obj.estimator.model())
            
            
            %% The estimated sensor measurements
            % `estimator.sensors()` gets used sensors (returns `SensorList`)
            % ex: `estimator.sensors.getNrOfSensors(iDynTree.ACCELEROMETER)`
            %     `estimator.sensors.getSensor(iDynTree.ACCELEROMETER,1)`
            obj.estMeasurements = iDynTree.SensorsMeasurements(obj.estimator.sensors);
            
            % Memory allocation for unused output variables
            obj.sink1 = iDynTree.LinkContactWrenches(obj.estimator.model);
            obj.sink2 = iDynTree.JointDOFsDoubleArray(obj.dofs);
            
            % estimation outputs
            obj.estimatedSensorLinAcc = iDynTree.LinearMotionVector3();
            
            % measurements
            obj.tmpSensorLinAcc = iDynTree.LinearMotionVector3();
            
            % full traversal for computing the base to link k transforms
            obj.traversal_Lk = iDynTree.Traversal();
            obj.linkPos = iDynTree.LinkPositions(obj.estimator.model);
            
        end
        
        function Dq0 = buildSensorsNjointsIDynTreeListsForActivePart(obj,data,modelParams)
            %% Select sensors indices from iDynTree model, matching the list 'jointsToCalibrate'.
            % Go through 'data.frames', 'data.parts' and 'data.labels' and build :
            % - the joint list (controlled) mapped into the iDynTree indices
            % - the sensor list for the current part (part: right_leg, left_arm,...).
            % This is a list of indexes, that will be later used for retrieving the
            % sensor predicted measurements and the real measure from the captured data.
            
            %=== Mapping the inertial sensors measurements to iDynTree
            %
            % obj.sensorsIdxListFile, obj.sensorsIdxListModel
            
            allDataTypeIdxes = 1:numel(data.type);
            % Identify the inertial sensor frames in the 'data' structure
            obj.sensorsIdxListFile = allDataTypeIdxes(ismember(data.type,{'inertialMTB','inertial'}));
            
            % Get respective indexes from the model
            obj.sensorsIdxListModel = cellfun(@(frame) ...
                obj.estimator.sensors.getSensorIndex(iDynTree.ACCELEROMETER,char(frame)),...
                data.frames(obj.sensorsIdxListFile),...
                'UniformOutput',false);
            obj.sensorsIdxListModel = cell2mat(obj.sensorsIdxListModel);
            
            %=== Mapping the joint encoders measurements to iDynTree
            %
            % obj.jointsIdxFile, obj.ctrledJointsIdxFromModel
            %
            % obj.q0i, obj.dqi, obj.d2qi
            
            % Identify the joint state frames in the 'data' structure
            obj.jointsIdxFile = allDataTypeIdxes(ismember(data.type,{'stateExt:i'}));
            
            % Get the respective controlled parts in 'data'
            modelParamsCtrledParts = data.parts(obj.jointsIdxFile);
            
            % Get respective indexes in 'modelParams'
            modelParamsCtrledPartsIdxes = cellfun(@(key) ...
                modelParams.jointsToCalibrate.mapIdx(key),...
                modelParamsCtrledParts,...
                'UniformOutput',true);
            
            % Get full list of controlled joints. The order in
            % '.ctrledJoints' list has to match the one of the q vector in
            % stateExt:o yarp port.
            modelParamsCtrledJoints = [modelParams.jointsToCalibrate.ctrledJoints{modelParamsCtrledPartsIdxes}];
            
            % Get respective controlled joints indexes from iDynTree
            obj.ctrledJointsIdxFromModel = ...
                cellfun(@(joint) ...
                1 + obj.estimator.model.getJointIndex(joint),...
                modelParamsCtrledJoints,...
                'UniformOutput',true);
            
            % Select from label index the joints associated to the current processed part.
            [obj.q0i,obj.dqi,obj.d2qi] = cellfun(@(label) deal(...
                data.parsedParams.(['qsRad_' label])',...
                data.parsedParams.(['dqsRad_' label])',...
                data.parsedParams.(['d2qsRad_' label])'),...
                data.labels(obj.jointsIdxFile),...
                'UniformOutput',false);
            % Transpose the resulting matrices (q dimension -> lines, time dimension -> columns)
            obj.q0i  = [obj.q0i{:}]';
            obj.dqi  = [obj.dqi{:}]';
            obj.d2qi = [obj.d2qi{:}]';
            
            %% === Map the calibration joint position vectors Dq and Dq0 to iDynTree
            %
            %      (no need to map them to the read qi,dqi,d2qi. these
            %      vectors will be set directly by the optimization solver
            %      and added to the iDynTree vector.
            
            % Get indexes of calibrated parts
            [~,calibedPartsIdxes] = ...
                ismember(modelParams.calibedParts,modelParams.jointMeasedParts);
            
            % Get full list of calibrated joints and starting point offset Dq0
            if ~isempty(calibedPartsIdxes)
                [modelParamsCalibedJoints,modelParamsCalibedDq0] = cellfun(...
                    @(joints,calibedDq0,calibedIdxes) deal(...
                    joints(calibedIdxes),calibedDq0(calibedIdxes)),...
                    modelParams.jointsToCalibrate.ctrledJoints(calibedPartsIdxes),...
                    modelParams.jointsToCalibrate.calibedJointsDq0(calibedPartsIdxes),...
                    modelParams.jointsToCalibrate.calibedJointsIdxes(calibedPartsIdxes),...
                    'UniformOutput',false);
                modelParamsCalibedJoints = [modelParamsCalibedJoints{:}];
                [Dq0,obj.Dq0] = deal(cell2mat(modelParamsCalibedDq0)); % decapsulation
                [Dq0,obj.Dq0] = deal(Dq0(:),obj.Dq0(:)); % make sure they are vertical vectors
            else
                modelParamsCalibedJoints = {};
                [Dq0,obj.Dq0] = deal([],[]);
            end
            
            % Get respective calibrated joints indexes from iDynTree
            obj.calibJointsIdxFromModel = ...
                cellfun(@(joint) ...
                1 + obj.estimator.model.getJointIndex(joint),...
                modelParamsCalibedJoints,...
                'UniformOutput',true);
        end
        
        function loadJointNsensorsDataSubset(obj,subsetVec_idx)
            % Select a time subset of the joint positions
            obj.sub_q0i = obj.q0i(:,subsetVec_idx);
            obj.sub_dqi = obj.dqi(:,subsetVec_idx);
            obj.sub_d2qi = obj.d2qi(:,subsetVec_idx);
        end

        function simulateAccelerometersMeasurements(obj, data, datasetVecIdx)
            for ts = 1:length(datasetVecIdx)
                % Fill iDynTree joint vectors.
                % Warning!! iDynTree takes in input **radians** based units,
                % while the iCub port stream **degrees** based units.
                qisRobotDOF = zeros(obj.dofs,1); qisRobotDOF(obj.ctrledJointsIdxFromModel,1) = obj.sub_q0i(:,ts);
                dqisRobotDOF = zeros(obj.dofs,1); dqisRobotDOF(obj.ctrledJointsIdxFromModel,1) = obj.sub_dqi(:,ts);
                d2qisRobotDOF = zeros(obj.dofs,1); d2qisRobotDOF(obj.ctrledJointsIdxFromModel,1) = obj.sub_d2qi(:,ts);
                obj.qi_idyn.fromMatlab(qisRobotDOF);
                obj.dqi_idyn.fromMatlab(dqisRobotDOF);
                obj.d2qi_idyn.fromMatlab(d2qisRobotDOF);
                
                % Update the kinematics information in the estimator
                obj.estimator.updateKinematicsFromFixedBase(obj.qi_idyn,obj.dqi_idyn,obj.d2qi_idyn, ...
                    obj.base_link_index,obj.grav_idyn);
                
                % run the estimation
                obj.estimator.computeExpectedFTSensorsMeasurements(obj.fullBodyUnknowns,obj.estMeasurements,obj.sink1,obj.sink2);
                
                % Get predicted sensor data for each sensor referenced in 'sensorsIdxList'
                % and write them into the 'data' structure.
                for acc_i = 1:length(obj.sensorsIdxListModel)
                    % get predicted measurement on sensor frame
                    obj.estMeasurements.getMeasurement(iDynTree.ACCELEROMETER,obj.sensorsIdxListModel(acc_i),obj.estimatedSensorLinAcc);
                    sensEst = obj.estimatedSensorLinAcc.toMatlab;
                    
                    % get measurement table ys_xxx_acc [3xnSamples] from captured data,
                    % and then select the sample 's' (<=> timestamp).
                    ys   = ['ys_' data.labels{obj.sensorsIdxListFile(acc_i)}];
                    eval(['data.parsedParams.' ys '(:,subsetVec_idx(ts)) = sensEst;']);
                end
            end
        end

        function [e,sensMeasCell,sensEstCell] = costFunctionSigma(obj,Dq, data, subsetVec_idx, optimFunction, log, optimized)
            %COSTFUNCTIONSIGMA Summary of this function goes here
            %   Detailed explanation goes here
            %
            %% compute predicted measurements
            % We compute here the final cost 'e'. As it is a sum of norms, we can also
            % compute it as :   v^\top \dot v    , v being a vector concatenation of
            % all the components of the sum. Refer to equation(1) in https://bitbucket.org/
            % gnuno/jointoffsetcalibinertialdoc/src/6c2f99f3e1be59c8021e4fc5e522fa21bdd97037/
            % Papers/PaperOnOffsetsCalibration.svg?at=fix/renderingMindmaps
            %
            % 'costVec' will be a cell array of cells 'costVec_ts'
            costVec_ts = cell(length(obj.sensorsIdxListModel),1);
            costVec = cell(length(subsetVec_idx),1);
            
            %DEBUG
            sensMeasNormMat = zeros(length(subsetVec_idx),length(obj.sensorsIdxListModel));
            sensEstNormMat = zeros(length(subsetVec_idx),length(obj.sensorsIdxListModel));
            costNormMat = zeros(length(subsetVec_idx),length(obj.sensorsIdxListModel));
            angleMat = zeros(length(subsetVec_idx),length(obj.sensorsIdxListModel));
            qiMat = zeros(length(subsetVec_idx),obj.dofs);
            
            sensMeasCell = cell(length(subsetVec_idx),length(obj.sensorsIdxListModel));
            sensEstCell = cell(length(subsetVec_idx),length(obj.sensorsIdxListModel));
            
            for ts = 1:length(subsetVec_idx)
                
                % Fill iDynTree joint vectors.
                % Warning!! iDynTree takes in input **radians** based units,
                % while the iCub port stream **degrees** based units.
                qisRobotDOF = zeros(obj.dofs,1); qisRobotDOF(obj.ctrledJointsIdxFromModel,1) = obj.sub_q0i(:,ts);
                dqisRobotDOF = zeros(obj.dofs,1);% dqisRobotDOF(obj.ctrledJointsIdxFromModel,1) = obj.sub_dqi(:,ts);
                d2qisRobotDOF = zeros(obj.dofs,1);% d2qisRobotDOF(obj.ctrledJointsIdxFromModel,1) = obj.sub_d2qi(:,ts);
                % Add Dq for the optimization function obj.calibJointsIdxFromModel
                qisRobotDOF(obj.calibJointsIdxFromModel,1) = qisRobotDOF(obj.calibJointsIdxFromModel,1) + Dq;

                obj.qi_idyn.fromMatlab(qisRobotDOF);
                obj.dqi_idyn.fromMatlab(dqisRobotDOF);
                obj.d2qi_idyn.fromMatlab(d2qisRobotDOF);
                
                % DEBUG
                modelJointsList = obj.ctrledJointsIdxFromModel;
                qiMat(ts,:) = qisRobotDOF';
                
                % Update the kinematics information in the estimator
                obj.estimator.updateKinematicsFromFixedBase(obj.qi_idyn,obj.dqi_idyn,obj.d2qi_idyn, ...
                                                            obj.base_link_index,obj.grav_idyn);
                
                % run the estimation
                obj.estimator.computeExpectedFTSensorsMeasurements(obj.fullBodyUnknowns,obj.estMeasurements,obj.sink1,obj.sink2);
                
                % Get predicted and measured sensor data for each sensor referenced in
                % 'sensorsIdxList' and build a single 'diff' vector for the whole data set.
                for acc_i = 1:length(obj.sensorsIdxListModel)
                    % get predicted measurement on sensor frame
                    obj.estMeasurements.getMeasurement(iDynTree.ACCELEROMETER,obj.sensorsIdxListModel(acc_i),obj.estimatedSensorLinAcc);
                    sensEst = obj.estimatedSensorLinAcc.toMatlab;
                    
                    % get measurement table ys_xxx_acc [3xnSamples] from captured data,
                    % and then select the sample 's' (<=> timestamp).
                    ys   = ['ys_' data.labels{obj.sensorsIdxListFile(acc_i)}];
                    eval(['sensMeas = data.parsedParams.' ys '(:,subsetVec_idx(ts));']);
                    
                    % compute the cost for 1 sensor / 1 timestamp
                    costVec_ts{acc_i} = (sensMeas - sensEst);
                    %DEBUG
                    sensMeasNormMat(ts,acc_i) = norm(sensMeas,2);
                    sensEstNormMat(ts,acc_i) = norm(sensEst,2);
                    costNormMat(ts,acc_i) = norm(costVec_ts{acc_i},2);
                    % compute angle
                    sinAngle = norm(cross(sensEst,sensMeas),2)/(norm(sensEst,2)*norm(sensMeas,2));
                    cosAngle = (sensEst'*sensMeas)/(norm(sensEst,2)*norm(sensMeas,2));
                    angleMat(ts,acc_i) = atan2(sinAngle,cosAngle);
                    sensMeasCell{ts,acc_i} = sensMeas';
                    sensEstCell{ts,acc_i} = sensEst';
                end
                
                costVec{ts} = cell2mat(costVec_ts);
            end
            
            
            % Final cost = norm of 'costVec'
            costVecMat = cell2mat(costVec);
            optimFunctionProps = functions(optimFunction);
            if strcmp(optimFunctionProps.function,'lsqnonlin')
                e = costVecMat;
            else
                e = costVecMat'*costVecMat;
            end
            
            if log
                % log data
                logFile = ['./data/logSensorMeasVsEst' optimized '.mat'];
                save(logFile,'modelJointsList','qiMat','sensMeasNormMat','sensEstNormMat','costNormMat','angleMat','sensMeasCell','sensEstCell','subsetVec_idx');
            end
        end
        
        function e = costFunctionSigmaProjOnEachLink(obj,Dq,data,subsetVec_idx,optimFunction)
            % We had defined in 'buildModelParams' a segment i as a link for which
            % parent joint i and joint i+1 axis are not concurrent. For instance 'root_link',
            % 'r_upper_leg', 'r_lower_leg', 'r_foot' are segments of the right leg. 'r_hip_1',
            % 'r_hip2' and r_hip_3' are part of the 3 DoF hip joint.
            % This function computes a sub-cost function e_k for each segment k. Each
            % cost e_k is the sum of variances of all the sensor measurements projected
            % on the link k frame F_k.
            %
            %% compute predicted measurements
            % We compute here the final cost 'e'. As it is a sum of norms, we can also
            % compute it as :   v^\top \dot v    , v being a vector concatenation of
            % all the components of the sum. Refer to equation(1) in https://bitbucket.org/
            % gnuno/jointoffsetcalibinertialdoc/src/6c2f99f3e1be59c8021e4fc5e522fa21bdd97037/
            % Papers/PaperOnOffsetsCalibration.svg?at=fix/renderingMindmaps
            %
            % 'costVec_Lk_ts' is an array of costs for 1 frame projection, 1 timestamp 
            % and *per* sensor.
            % 'costVec_Lk' is an array of costs for 1 frame projection, *per* timestamp
            % and *per* sensor.
            % 'costVec' is an array of costs for *per* frame projection, *per* timestamp
            % and *per* sensor.
            costVec_Lk_ts = cell(length(obj.sensorsIdxListModel),1);
            costVec_Lk = cell(length(subsetVec_idx),1);
            costVec = cell(length(obj.segments),1);
            
            %DEBUG
            % sensMeasNormMat = zeros(length(subsetVec_idx),length(obj.sensorsIdxListModel));
            % sensEstNormMat = zeros(length(subsetVec_idx),length(obj.sensorsIdxListModel));
            % costNormMat = zeros(length(subsetVec_idx),length(obj.sensorsIdxListModel));
            % 
            % sensMeasCell = cell(length(subsetVec_idx),length(obj.sensorsIdxListModel));
            % sensEstCell = cell(length(subsetVec_idx),length(obj.sensorsIdxListModel));

            %% Sum the costs projected on every link (we later might exclude the base
            % link which doesn't have accelerometers and assume a theoretical g_0.
            %
            % Definition:
            %
            % $$e_T = \sum_{k=0}^{N} e_k$$
            %
            for segmentk = 1:length(obj.segments)
                %% Compute the mean of measurements projected on link Lk
                %
                % Definition:
                %
                % $${}^k\mu_{g,k} = \frac{1}{PM} \sum_{p=1}^{P} \sum_{i=0}^{M} {{}^kR_{S_i}}(q_p,\Delta q) {}^{S_i}g_i(p)$$
                %
                %  Considering the following notation:
                %
                % $N$: number of links/joints in the chain, except link 0.
                % $M$: number of sensors. Each link can have several sensors attached
                % to it ($M \geq N$).
                % $S_i$: sensor $i$ frame.
                % ${}^{S_i}g_i(p)$: gravity measurement from sensor $i$, for a given
                % kinematic chain configuration $p$, expressed in the sensor $i$ frame.
                %  $G$: ground truth gravity vector.
                %  ${}^bR_a$: for any frame $a$ or $b$, rotation matrix transforming
                %  motion. vector coordinates from frame $a$ to frame $b$ (link root frames).
                %  $p$: static configuration of the kinematic chain, for a given set of
                %  measurements.
                %  $P$: number of static configurations used for capturing data.
                %  $q_p$: vector of all the joint angular positions (joint encoders reading) of the
                %  kinematic chain for a static configuration $p$.
                %  $\Delta q$: vector of encoder offsets.
                %
                
                % init the 2D array of measurements projected on link k, and their mean
                Lk_sensMeasCell = cell(length(subsetVec_idx),length(obj.sensorsIdxListModel));
                mu_k = cell(length(subsetVec_idx),1);
                
                % set 'Lk' as the traversal base to be used at current
                % iteration
                Lk = obj.estimator.model.getLinkIndex(obj.segments{segmentk});
                obj.estimator.model.computeFullTreeTraversal(obj.traversal_Lk, Lk);
                
                
                for ts = 1:length(subsetVec_idx)
                    
                    % Complete the full floating base position configuration
                    % by filling the joint positions.
                    % Warning!! iDynTree takes in input **radians** based units,
                    % while the iCub port stream **degrees** based units.
                    % Also add joint offsets from a previous result.
                    qisRobotDOF = zeros(obj.dofs,1); qisRobotDOF(obj.ctrledJointsIdxFromModel,1) = obj.sub_q0i(:,ts);
                    % Add Dq for the optimization function obj.calibJointsIdxFromModel
                    qisRobotDOF(obj.calibJointsIdxFromModel,1) = qisRobotDOF(obj.calibJointsIdxFromModel,1) + Dq;
                    % obj.qi_idyn.fromMatlab(qisRobotDOF);
                    for joint_i = 0:(obj.dofs-1)
                        obj.fixedBasePos.jointPos.setVal(joint_i,qisRobotDOF(joint_i+1));
                    end
                    
                    % Project on link frame Lk all measurements from each sensor referenced in
                    % 'sensorsIdxList'and compute the mean.
                    for acci = 1:length(obj.sensorsIdxListModel)
                        % get sensor handle
                        sensor = obj.estimator.sensors.getAccelerometerSensor(obj.sensorsIdxListModel(acci));
                        % get the sensor to link i transform Li_H_acci
                        Li_H_acci = sensor.getLinkSensorTransform().getRotation().toMatlab;
                        % get the projection link k to link i transform Lk_H_Li
                        iDynTree.ForwardPositionKinematics(obj.estimator.model, obj.traversal_Lk, ...
                            obj.fixedBasePos, obj.linkPos);
                        Li = sensor.getParentLinkIndex();
                        Lk_H_Li_idyn = obj.linkPos(Li);
                        Lk_H_Li = Lk_H_Li_idyn.getRotation().toMatlab;
                        % get measurement table ys_xxx_acc [3xnSamples] from captured data,
                        % and then select the sample 's' (<=> timestamp).
                        ys   = ['ys_' data.labels{obj.sensorsIdxListFile(acci)}];
                        eval(['sensMeas = data.parsedParams.' ys '(:,ts);']);
                        % project the measurement in link Lk frame and store it for
                        % later computing the variances
                        Lk_sensMeasCell{ts,acci} = Lk_H_Li * (Li_H_acci * sensMeas);
                    end
                    % compute the mean
                    mu_k{ts} = mean(cell2mat(Lk_sensMeasCell(ts,:)),2);
                end
                
                %% Compute the variances of measurements projected on link Lk
                %
                % Definition:
                %
                % $$e_k = \sum_{p=1}^{P} \sum_{i=0}^{M} \Vert {}^kR_{S_i}(q_p,\Delta q) {}^{S_i}g_i(p) - {{}^k\mu_{g,k}} \Vert^2$$
                %
                % Considering the same previous notation, and the following additions:
                % $k$: link frame where we project the measurements
                % $N$: total number of links
                %
                % Compute the variances for each ts and acc_i. Formulate computation
                % as variance = diff' * diff.
                for ts = 1:length(subsetVec_idx)
                    for acci = 1:length(obj.sensorsIdxListModel)
                        % compute the cost for 1 sensor / 1 timestamp, using previously
                        % computed measurement (ts,acci) and mean(ts), and previously
                        % computed mean, all projected on frame link k.
                        costVec_Lk_ts{acci} = (Lk_sensMeasCell{ts,acci} - mu_k{ts});
                        %DEBUG
                        %             sensMeasNormMat(ts,acci) = norm(sensMeas,2);
                        %             sensEstNormMat(ts,acci) = norm(sensEst,2);
                        %             costNormMat(ts,acci) = norm(costVec_Lk_ts{acci},2);
                        %             sensMeasCell{ts,acci} = sensMeas';
                        %             sensEstCell{ts,acci} = sensEst';
                    end
                    
                    costVec_Lk{ts} = cell2mat(costVec_Lk_ts);
                end
                costVec{segmentk} = cell2mat(costVec_Lk);
            end
            
            % Final cost = norm of 'costVec'
            costVecMat = cell2mat(costVec);
            optimFunctionProps = functions(optimFunction);
            if strcmp(optimFunctionProps.function,'lsqnonlin')
                e = costVecMat;
            else
                e = costVecMat'*costVecMat;
            end
          
        end
        
        function list_kHsens = getListTransforms(obj,refFrameName)
            % Set joint positions to 0
            qisRobotDOF = zeros(obj.dofs,1);
            dqisRobotDOF = zeros(obj.dofs,1);
            d2qisRobotDOF = zeros(obj.dofs,1);
            obj.qi_idyn.fromMatlab(qisRobotDOF);
            obj.dqi_idyn.fromMatlab(dqisRobotDOF);
            obj.d2qi_idyn.fromMatlab(d2qisRobotDOF);
            
            % init list of transforms
            nbSensors = obj.estimator.sensors.getNrOfSensors(iDynTree.ACCELEROMETER);
            list_kHsens = cell(nbSensors,1);
            
            % get link from ref frame and compute the traveral
            Lb = obj.estimator.model.getFrameLink(...
                obj.estimator.model.getFrameIndex(refFrameName));
            obj.estimator.model.computeFullTreeTraversal(obj.traversal_Lk, Lb);
            
            % propagate kinematic parameters
            iDynTree.ForwardPositionKinematics(obj.estimator.model, obj.traversal_Lk,obj.fixedBasePos, obj.linkPos);
            
            % get the transform for each sensor
            for acci = 1:nbSensors
                % get sensor handle
                sensor = obj.estimator.sensors.getAccelerometerSensor(acci-1);
                % get the sensor to link i transform Li_H_acci
                Li_H_acci = sensor.getLinkSensorTransform().getRotation().toMatlab;
                % get the projection link b to link i transform Lb_H_Li
                iDynTree.ForwardPositionKinematics(obj.estimator.model, obj.traversal_Lk, ...
                    obj.fixedBasePos, obj.linkPos);
                Li = sensor.getParentLinkIndex();
                Lb_H_Li_idyn = obj.linkPos(Li);
                Lb_H_Li = Lb_H_Li_idyn.getRotation().toMatlab;
                % get the transform base link to sensor frame
                Lb_H_acci = Lb_H_Li * Li_H_acci;
                % print
                fprintf('Sensor %s :',sensor.getName());
                Lb_H_Li
                Li_H_acci
                Lb_H_acci
                % export list
                list_kHsens{acci,1} = Lb_H_acci;
            end
        end
    end
end

