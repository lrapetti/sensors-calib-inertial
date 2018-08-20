function ok = stop(obj)
%Stop the internal thread

if isempty(obj.thread)
    warning([...
        'Internal thread not set!! Either create internal thread using '...
        'obj.createThread(...), or use an external one.']);
else
    obj.thread.stop(true);
end

end
