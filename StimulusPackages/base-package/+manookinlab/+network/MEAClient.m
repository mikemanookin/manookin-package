classdef MEAClient < handle
    
    properties (Access = private, Transient)
        socket
    end
    
    properties (Access = private)
        readTimeout
    end
    
    methods
        
        function obj = MEAClient()
            obj.socket = java.net.Socket();
            
            obj.readTimeout = 10;
        end
        
        function delete(obj)
            obj.close();
        end
        
        function connect(obj, host, port)
            % Connects to the specified host ip on the specified port.
            
            addr = java.net.InetSocketAddress(host, port);
            timeout = 10000;
            
            try
                obj.socket.connect(addr, timeout);
            catch x
                error(char(x.ExceptionObject.getMessage()));
            end
        end
        
        function close(obj)
            obj.socket.close();
        end
        
        function writeString(obj, v)
            try
                writer = java.io.PrintWriter(obj.socket.getOutputStream());
            catch x
                if isa(x, 'matlab.exception.JavaException')
                    error(char(x.ExceptionObject.getMessage()));
                end
                rethrow(x);
            end
            
            try
                writer.println(v);
%                 writer.write(v);
%                 writer.flush();
%                 writer.close();
            catch x
                if isa(x, 'matlab.exception.JavaException')
                    error(char(x.ExceptionObject.getMessage()));
                end
                rethrow(x);
            end
        end
        
        function write(obj, varargin)
            try
                stream = java.io.ObjectOutputStream(obj.socket.getOutputStream());
            catch x
                if isa(x, 'matlab.exception.JavaException')
                    error(char(x.ExceptionObject.getMessage()));
                end
                rethrow(x);
            end
            
            bytes = getByteStreamFromArray(varargin);
            
            try
                stream.writeObject(bytes);
            catch x
                if isa(x, 'matlab.exception.JavaException')
                    error(char(x.ExceptionObject.getMessage()));
                end
                rethrow(x);
            end
        end
        
        function fname = getFileName(obj, timeout)
            fname = '';
            try
                fname = obj.listenToServer(timeout);
                fname = char(fname);
            catch
            end
        end
        
        function result = listenToServer(obj, timeout)
            % Timeout in seconds.
            in = obj.socket.getInputStream();
            
            start = tic;
            while in.available() == 0
                if timeout > 0 && toc(start) >= timeout
                    error('TcpConnection:ReadTimeout', 'Read timeout');
                end
            end
            
            stream = java.io.ObjectInputStream(in);
            
            result = stream.readObject();
            
%             varargout = getArrayFromByteStream(typecast(result, 'uint8'));
        end
        
        function result = read(obj)
            in = obj.socket.getInputStream();
            
            start = tic;
            while in.available() == 0
                if obj.readTimeout > 0 && toc(start) >= obj.readTimeout
                    error('TcpConnection:ReadTimeout', 'Read timeout');
                end
            end
            
            stream = java.io.ObjectInputStream(in);
            
            result = stream.readObject();
            
%             varargout = getArrayFromByteStream(typecast(result, 'uint8'));
        end
    end
end