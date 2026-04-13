function testMEADeviceSideChannel()
% testMEADeviceSideChannel - Test the side-channel filename protocol.
%
% This script tests that MEADevice can receive a filename from the Java
% FileNameNotifier via the lightweight DataOutputStream.writeUTF() protocol,
% without needing LabView, Vision, or any external hardware.
%
% PREREQUISITES:
%   The Vision.jar must be on your Java classpath. You can add it by:
%     1. Edit your javaclasspath.txt or call:
%        javaaddpath('/path/to/vision7_symphony/Vision.jar')
%     2. Or run 'ant dist' in vision7_symphony/ first to build the jar.
%
% USAGE:
%   >> testMEADeviceSideChannel
%
% The test spawns a Java thread that sends a test filename to MEADevice's
% ServerSocket after a short delay, then verifies that MEADevice received
% the correct filename.

    import java.io.*;
    import java.net.*;

    testPort = 19001; % Use a non-standard port to avoid conflicts
    testFileName = '2024-06-15/data042/data042000.bin';

    fprintf('\n==========================================\n');
    fprintf('  MEADevice Side-Channel Test (Matlab)\n');
    fprintf('==========================================\n\n');

    % =====================================================================
    % Test 1: Direct protocol test (bypass MEADevice, test raw protocol)
    % =====================================================================
    fprintf('--- Test 1: Raw side-channel protocol ---\n');

    % Start a ServerSocket
    server = ServerSocket(testPort);
    server.setSoTimeout(10000);
    fprintf('  Server listening on port %d\n', testPort);

    % Spawn a Java thread that sends the filename after a short delay
    sender = edu.ucsc.neurobiology.vision.testing.SideChannelSender(testPort, testFileName, 500);
    senderThread = java.lang.Thread(sender);
    senderThread.start();

    % Accept connection and read filename
    try
        clientSocket = server.accept();
        fprintf('  Client connected.\n');

        inputStream = clientSocket.getInputStream();
        dis = java.io.DataInputStream(inputStream);
        receivedName = char(dis.readUTF());
        fprintf('  Received filename: %s\n', receivedName);

        dis.close();
        clientSocket.close();

        if strcmp(receivedName, testFileName)
            fprintf('  PASS: Filename matches!\n\n');
        else
            fprintf('  FAIL: Expected "%s" but got "%s"\n\n', testFileName, receivedName);
        end
    catch e
        fprintf('  FAIL: %s\n\n', e.message);
    end

    server.close();
    senderThread.join(5000);

    % =====================================================================
    % Test 2: Full MEADevice integration test
    % =====================================================================
    fprintf('--- Test 2: MEADevice integration ---\n');

    meaPort = 19002;

    % Create MEADevice (the class under test)
    try
        mea = manookinlab.devices.VisionCommDevice(meaPort);
        fprintf('  Created VisionCommDevice on port %d\n', meaPort);
    catch e
        fprintf('  SKIP: Could not create VisionCommDevice (Symphony not on path?)\n');
        fprintf('         Error: %s\n', e.message);
        fprintf('         Test 1 already validated the protocol.\n');
        return;
    end

    testFileName2 = '2024-09-22/data099/data099000.bin';

    % Spawn a sender that will connect after MEADevice starts listening
    sender2 = edu.ucsc.neurobiology.vision.testing.SideChannelSender(meaPort, testFileName2, 1000);
    senderThread2 = java.lang.Thread(sender2);
    senderThread2.start();

    % Start MEADevice (this blocks until it receives the filename or times out)
    fprintf('  Starting VisionCommDevice.start() ...\n');
    try
        mea.start();

        receivedName2 = char(mea.fileName);
        fprintf('  VisionCommDevice.fileName = %s\n', receivedName2);

        if strcmp(receivedName2, testFileName2)
            fprintf('  PASS: VisionCommDevice received the correct filename!\n\n');
        else
            fprintf('  FAIL: Expected "%s" but got "%s"\n\n', testFileName2, receivedName2);
        end
    catch e
        fprintf('  FAIL: VisionCommDevice.start() threw: %s\n\n', e.message);
    end

    senderThread2.join(5000);

    fprintf('==========================================\n');
    fprintf('  Tests complete.\n');
    fprintf('==========================================\n');
end


% =========================================================================
% Helper: A Java Runnable that sends a filename via DataOutputStream.writeUTF()
% =========================================================================
% This is defined as a local Java-compatible class. Since Matlab can't
% easily define Java Runnables inline, we use a small helper class below.
% If FileNameNotifier is on the classpath, we use it directly instead.
