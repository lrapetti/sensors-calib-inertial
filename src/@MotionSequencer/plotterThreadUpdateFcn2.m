function plotterThreadUpdateFcn2( obj )
%Plots current joint torque and velocity

% get index of the controlled motors
pwmCtrledMotorIdx = obj.ctrlBoardRemap.getMotorsMappedIdxes({obj.sequences{obj.seqIdx}.pwmctrl.motor});

% get motor velocity (degrees/s from the robot interface) and convert it to the
% units defined in the online plotter
motorVelDeg = obj.ctrlBoardRemap.getMotorEncoderSpeeds(pwmCtrledMotorIdx);
motorVel = obj.tempPlot.convertFromDeg(motorVelDeg);

% get the motor torque from the respective coupled joints torques
motorCurr = obj.ctrlBoardRemap.getCurrents(pwmCtrledMotorIdx);

% plot the quantities
addpoints(obj.tempPlot.an,motorVel,motorCurr);
drawnow limitrate

end

