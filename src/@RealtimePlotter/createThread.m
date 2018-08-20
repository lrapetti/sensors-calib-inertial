function [ ok ] = createThread( obj,threadPeriod,threadTimeout )
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here

% if there is a plotting thread already running shut it down and destroy it
if ~isempty(obj.thread)
    if obj.thread.isRunning()
        obj.thread.stop(true);
    end
    delete(obj.thread);
end

startFcn  = @(~,~) obj.threadStartFcn();
stopFcn   = @(~,~) obj.threadStopFcn();
updateFcn = @(~,~,~) obj.threadUpdateFcn();

obj.thread = RateThread(...
    updateFcn,startFcn,stopFcn,'local',...
    threadPeriod,threadTimeout);

end
