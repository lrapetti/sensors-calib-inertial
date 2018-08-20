function threadUpdateFcn( obj )
%Plots current target variables values

persistent frameIdx;
frameIdx = frameIdx+1;

% read the current variables values x,y.
% x: 1xn (n timestamps)
% y: jxn (n samples of j components)
[x_1xn,y_jxn] = obj.getVarToPlot_cb();

% set the range around the current (x,y) value
obj.setXlimits(max(x_1xn),obj.xLimits);
obj.setYlimits([min(min(y_jxn)) max(max(y_jxn))],obj.yLimits);

% update the plot points
for idx = 1:numel(obj.animLinesList)
    addpoints(obj.animLinesList{idx},x_1xn,y_jxn(idx,:));
end

drawnow limitrate nocallbacks;

end
