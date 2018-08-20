function [x,y] = getDataPoint( obj )
%UNTITLED2 Summary of this function goes here
%   Detailed explanation goes here

% get motor velocity (degrees/s from the robot interface) and convert it to the
% units defined in the online plotter
motorVelDeg = obj.ctrlBoardRemap.getMotorEncoderSpeeds(pwmCtrledMotorIdx);
motorVel = obj.tempPlot.convertFromDeg(motorVelDeg);

% get the motor torque from the respective coupled joints torques
motorCurr = obj.ctrlBoardRemap.getCurrents(pwmCtrledMotorIdx);

x = motorVel;
y = motorCurr;

end