function threadStartFcn( obj )

% Set x,y limits

switch obj.xLimitsMode
    case 'auto'
        xlim(obj.figureH.CurrentAxes,'auto');
        obj.setXlimits = @(~,~) [];
    case 'fixed'
        xlim(obj.figureH.CurrentAxes,obj.xLimits);
        obj.setXlimits = @(~,~) [];
    case 'follow'
        xlim(obj.figureH.CurrentAxes,obj.xLimits);
        obj.setXlimits = @(x,xLimits) xlim(obj.figureH.CurrentAxes,x+xLimits);
    otherwise
end

switch obj.yLimitsMode
    case 'auto'
        ylim(obj.figureH.CurrentAxes,'auto');
        obj.setYlimits = @(~,~) [];
    case 'fixed'
        ylim(obj.figureH.CurrentAxes,obj.yLimits);
        obj.setYlimits = @(~,~) [];
    case 'follow'
        ylim(obj.figureH.CurrentAxes,obj.yLimits);
        obj.setYlimits = @(y,yLimits) ylim(obj.figureH.CurrentAxes,y+yLimits);
    otherwise
end

end
