classdef MEADevice < symphonyui.core.Device
    
    properties
        fileName
    end
    
    properties (Access = private)
        server
        stopRequested
        port
        readTimeout
    end
    
    methods
        
        function obj = MEADevice(port)
            
            cobj = Symphony.Core.UnitConvertingExternalDevice('MEA@localhost', 'Unspecified', Symphony.Core.Measurement(0, symphonyui.core.Measurement.UNITLESS));
%             cobj = Symphony.Core.UnitConvertingExternalDevice(['MEA@' ip.Results.host], 'Unspecified', Symphony.Core.Measurement(0, symphonyui.core.Measurement.UNITLESS));
            obj@symphonyui.core.Device(cobj);
            obj.cobj.MeasurementConversionTarget = symphonyui.core.Measurement.UNITLESS;
%             import java.io.*;
%             import java.net.*;
%             import java.util.ArrayList;
%             import java.util.Collections;
%             import java.util.List;
%             import edu.ucsc.neurobiology.vision.util.*;
%             
            if nargin < 1
                port = 9002;
            end
            
            obj.readTimeout = 30000; % Timeout in milliseconds (30 sec to allow time for LabView→Vision handshake)
            
%             host = InetAddress.getLocalHost();
%             disp(['Local Host Name: ', host.getHostName()]);
            
%             obj.server = netbox.Server();
            obj.port = port;
            
%             addlistener(obj.server, 'ClientConnected', @obj.onClientConnected);
%             addlistener(obj.server, 'ClientDisconnected', @obj.onClientDisconnected);
%             addlistener(obj.server, 'EventReceived', @obj.onEventReceived);
%             addlistener(obj.server, 'Interrupt', @obj.onInterrupt);
        end
        
        function start(obj)
            import java.io.*;
            import java.net.*;

            obj.stopRequested = false;

            disp('Creating server socket...');
            try
                obj.server = ServerSocket(obj.port);
                % Set the timeout (must be in milliseconds).
                obj.server.setSoTimeout(obj.readTimeout);

                host = InetAddress.getLocalHost();
                disp(['Serving on host: ', char(host.getHostName()), ' and port: ', num2str(obj.port)]);

                while ~obj.stopRequested
                    clientSocket = obj.server.accept;
                    disp(['Client connected from ', char(clientSocket.getInetAddress().getHostAddress())]);
                    try
                        % Get the data stream.
                        inputStream = clientSocket.getInputStream();

                        % Read the filename via the lightweight side-channel protocol.
                        % The Java side sends the filename using DataOutputStream.writeUTF(),
                        % which we read here with DataInputStream.readUTF().
                        % This connection is completely independent of the data streaming
                        % pipeline, so closing it has no effect on other output streams.
                        dis = java.io.DataInputStream(inputStream);
                        obj.fileName = char(dis.readUTF());
                        disp(['Received filename: ', obj.fileName]);

                        obj.stopRequested = true;

                        % Close the side-channel socket. This is safe because it's
                        % a dedicated connection just for the filename, not part of
                        % the data streaming pipeline.
                        dis.close();
                        clientSocket.close();
                    catch x
                        if strcmp(x.identifier, 'TcpListen:AcceptTimeout')
                            notify(obj, 'Interrupt');
                            continue;
                        elseif strcmp(x.identifier, 'java.net.SocketTimeoutException')
                            obj.fileName = '';
                            disp('MEADevice waited too long for a connection from LabView/Vision...');
                            obj.server.close();
                            return;
                        else
                            rethrow(x);
                        end
                    end
                end
            catch x
                if strcmp(x.identifier, 'java.net.SocketTimeoutException')
                    obj.fileName = '';
                    disp('MEADevice waited too long for a connection from LabView/Vision...');
                    obj.server.close();
                    return;
                elseif strcmp(x.identifier, 'MATLAB:Java:GenericException')
                    obj.fileName = '';
                    disp('MEADevice waited too long for a connection from LabView/Vision...');
                    disp(x.identifier);
                    obj.server.close();
                    return;
                else
                    rethrow(x);
                end
            end
            obj.stop();
        end
        
        function stop(obj)
            % Automatically called when start completes.
            obj.server.close();
            return;
        end
        
    end
    
    methods (Access = protected)
        
        function onClientConnected(obj, ~, eventData) %#ok<INUSL>
            disp(['Client connected from ' eventData.connection.getHostName()]);
        end
    end
end
