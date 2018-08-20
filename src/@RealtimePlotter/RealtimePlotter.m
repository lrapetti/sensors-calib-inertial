classdef RealtimePlotter < handle
    %Plotter that can be attached to a rated thread for online plotting
    %   The class start/update/stop methods can be attached to a rated
    %   thread, or integrated in a runtime module design.
    
    properties (GetAccess=public, SetAccess=protected)
        figureH@matlab.ui.Figure;
        animLinesList@cell;
        markerCycles@double;
        xLimits@double;
        yLimits@double;
        xLimitsMode@char;
        yLimitsMode@char;
        setXlimits@function_handle;
        setYlimits@function_handle;
        getVarToPlot_cb@function_handle;
        thread@RateThread;
    end
    
    methods
        % Constructor
        function obj = RealtimePlotter(...
                figHandler,getVarToPlot_cb,animLinesList,markerCycles,...
                xLimitsMode,yLimitsMode,xLimits,yLimits)
            %xLimitsMode: 'fixed','auto','follow'
            
            % default init values. Controller not running...
            obj.figureH = figHandler;
            obj.getVarToPlot_cb = getVarToPlot_cb;
            obj.markerCycles = markerCycles;
            obj.xLimits = xLimits;
            obj.yLimits = yLimits;
            obj.xLimitsMode = xLimitsMode;
            obj.yLimitsMode = yLimitsMode;
            obj.animLinesList = animLinesList;
        end
        
        % Destructor
        function delete(obj)
            close(obj.figureH);
        end
        
        % Reset the animated line style
        setLineStyle(obj,lineStyle,marker,markerFaceColor,visible,selected);
        
        % Reset the limits
        setLimits(obj,xLimitsMode,yLimitsMode,xLimits,yLimits);
        
        % Create a thread for the real time plotting
        ok = createThread(obj,threadPeriod,threadTimeout);
        
        % Start the internal thread
        ok = start(obj);
        
        % Stop the internal thread
        ok = stop(obj);
        
        % Rate thread functions for the real-time plotter
        threadStartFcn(obj);
        threadStopFcn(obj);
        threadUpdateFcn(obj);
    end
    
end
