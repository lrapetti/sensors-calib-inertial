function threadStopFcn( obj )

switch obj.xLimitsMode
    case {'auto','follow'}
        xlim(obj.figureH.CurrentAxes,'auto');
        obj.setXlimits = @(~,~) [];
    case 'fixed'
        xlim(obj.figureH.CurrentAxes,obj.xLimits);
        obj.setXlimits = @(~,~) [];
    otherwise
end

switch obj.yLimitsMode
    case {'auto','follow'}
        ylim(obj.figureH.CurrentAxes,'auto');
        obj.setYlimits = @(~,~) [];
    case 'fixed'
        ylim(obj.figureH.CurrentAxes,obj.yLimits);
        obj.setYlimits = @(~,~) [];
    otherwise
end

end

