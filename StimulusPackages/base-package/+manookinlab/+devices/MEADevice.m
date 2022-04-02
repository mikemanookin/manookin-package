classdef MEADevice < symphonyui.core.Device
    
    properties
        fileName
    end
    
    properties (Access = private)
        stopRequested
        port
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
                port = 9001;
            end
            
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
            import java.util.ArrayList;
            import java.util.Collections;
            import java.util.List;
            import edu.ucsc.neurobiology.vision.util.*;
            
            obj.stopRequested = false;
            
            disp('Creating server socket...');
            myService = ServerSocket(obj.port);
            
            host = InetAddress.getLocalHost();
            disp(['Serving on host: ', char(host.getHostName()), ' and port: ', num2str(obj.port)]);
            
            while ~obj.stopRequested
                clientSocket = myService.accept;
                disp(['Client connected from ', char(clientSocket.getInetAddress().getHostAddress())]);
                try
                    % Get the data stream.
                    inputStream = clientSocket.getInputStream();
                    
                    % Parse the header from the input stream.
                    h = edu.ucsc.neurobiology.vision.io.RawDataHeader512(inputStream);

                    obj.fileName = [char(h.getExperimentIdentifier()), '\',char(h.getDatasetName()), '.bin'];
                    disp(obj.fileName)
                    
                    obj.stopRequested = true;
                    
                    % Close the socket.
                    inputStream.close();
                    clientSocket.close();
                catch x
                    if strcmp(x.identifier, 'TcpListen:AcceptTimeout')
                        notify(obj, 'Interrupt');
                        continue;
                    else
                        rethrow(x);
                    end
                end
            end
            myService.close();
            return;
        end
        
        function stop(obj)
            % Automatically called when start completes.
            
%             obj.server.requestStop();
            % TODO: Wait until tcpServer stops.
        end
        
    end
    
    methods (Access = protected)
        
        function onClientConnected(obj, ~, eventData) %#ok<INUSL>
            disp(['Client connected from ' eventData.connection.getHostName()]);
        end
    end
end