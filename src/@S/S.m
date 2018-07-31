classdef S < uint8
    %This class defines the possible states of the 'LowlevTauCtrlCalibrator' state machine.
    %   Detailed explanation goes here
    
    enumeration
        stateStart       (1)
        stateAcqFriction (2)
        stateFitFriction (3)
        stateAcqKgain    (4)
        stateFitKgain    (5)
        stateNextGroup   (6)
        stateEnd         (7)
    end
    
end
