function ok = start(obj)
%Start the internal thread

if isempty(obj.thread)
    warning([...
        'Internal thread not set!! Either create internal thread using '...
        'obj.createThread(...), or use an external one.']);
else
    ok = obj.thread.run(false); % run and don't wait for thread termination
end

end
