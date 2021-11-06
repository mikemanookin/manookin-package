package edu.ucsc.neurobiology.vision.io;

import java.io.*;
import java.net.*;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import edu.ucsc.neurobiology.vision.util.*;
// import java.nio.charset.Charset;
// import java.nio.charset.StandardCharsets;
// import java.util.stream.Collectors;


public class DataPipe {
    static String USAGE = "Arguments Required: " +
                      "\n 1. the port number for the server to listen on" +
                      "\n 2. the buffer size in Kb (try 64)" +
                      "\n 3. the saving mode (0 - blocking, 1 - asynchronous) + ";


    static ServerSocket myService = null;
    static MultipleCompressedSampleInputStream inputStream;

    // Check client connections.
    static boolean labviewConnected;
    static boolean symphonyConnected;


//     private MultipleCompressedSampleInputStream sampleInputStream;
//     private RawDataSaver dataSaver;

    static int port = 9876;
    static int bufferSize = 1024;
    static int saveMode = 1;
    static String outputServerName = "net://192.168.1.1/9000";
    static String rawDataSource = "net://192.168.1.2/7887";
    static int RUN_SPIKE_FINDING = 34; // Command for Vision (output server) to start spike finding

    static String commonPath = "";
    static int bufferSizeInBytes = 1024 * 200;
    static int nBuffers = 200;
    static int secondsToStream = 900;
    static int nSamplesToBuffer;
    static boolean waitForData = false;
    static String[] fileNames;
    static RawDataToVision dataSaver;

    static Socket symphonySocket;
    static Socket labviewSocket;

    public static void main(final String args[]) throws Exception {
        // Parse inputs
        if (args.length < 1 || args.length > 4) {
            System.out.println(USAGE);
            return;
        }
        try {
            port = Integer.parseInt(args[0]);
            if (args.length > 1) bufferSize          = Integer.parseInt(args[1]) * 1024;
            if (args.length > 2) saveMode            = Integer.parseInt(args[2]);
            if (args.length > 3) outputServerName    = args[3];
        } catch (NumberFormatException e) {
            System.out.println(USAGE);
            return;
        }

        nSamplesToBuffer = bufferSizeInBytes / 770;
        bufferSizeInBytes = nSamplesToBuffer * 770;

        labviewConnected = false;
        symphonyConnected = false;

        InetAddress host = InetAddress.getLocalHost();
        System.out.println("Local Host Name: " + host.getHostName());

        // Find IP address from local net, but not a loopback.  If there is none, use the first on the list.
        List<InetAddress> inets = new ArrayList<InetAddress>();
        List<NetworkInterface> netifaces = Collections.list(NetworkInterface.getNetworkInterfaces());
        for (NetworkInterface netiface : netifaces)
            inets.addAll(Collections.list(netiface.getInetAddresses()));
        host = inets.get(0);
        for (InetAddress inet : inets) {
            if (inet.isSiteLocalAddress() && !inet.isLoopbackAddress()) {
                host = inet;
                break;
            }
        }

        System.out.println("Local Host Address (clients should connect to): " + host.getHostAddress());
        System.out.print("Creating the server socket " + port + "...");
        myService = new ServerSocket(port, 0, host);
        System.out.println("done");

        // Parse the output paths.
        fileNames = StringUtil.decomposeString(outputServerName, ";");

        // Wait for connections.
        while (true) {
            System.out.println("Waiting for a client to connect...");
            final Socket clientSocket = myService.accept();
            System.out.println("Client connected from " + clientSocket.getInetAddress().getHostAddress());

            String address = clientSocket.getInetAddress().getHostAddress();

            // Check the client address to determine which computer your getting.
            if (address.equals("192.168.1.2")) {
              System.out.println("Received connection from LabView...");
              labviewConnected = true;

              Thread labviewThread = new Thread() {
                  public void run() {
                      try {
                          System.out.println("Grabbing input stream...");
                          inputStream = new MultipleCompressedSampleInputStream(rawDataSource, bufferSizeInBytes, nBuffers, waitForData);

                          // Start the input stream.
                          inputStream.start();

                          if (rawDataSource.startsWith("net://")) {
                              System.out.println("Sending commence signal to DAQ computer");
                              inputStream.commenceWriting();
                          }

                          // May need to read the command integer from LabView so the header is correct..
                          // try {
                          //     dis = new DataInputStream(clientSocket.getInputStream());
                          //     command = dis.readInt();
                          // } catch (IOException ex) {
                          //     System.err.println("Could not read command");
                          //     continue;
                          // }

                          System.out.println("Reading data header...");
                          RawDataHeader512 header = inputStream.getHeader();
//                             ID = header.getDatasetIdentifier().trim();
                          System.out.println("done");

                          System.out.println("Parsing the file name...");
                          // new File(header.getExperimentIdentifier()).mkdirs();
                          String fileName =
                              header.getExperimentIdentifier() + File.separator +
                              header.getDatasetName() + ".bin";

                          System.out.println(fileName);

                          // Check if Symphony is connected.
                          // line = brinp.readLine();
                          // if ((line == null) || line.equalsIgnoreCase("QUIT")) {
                          // }

                          // Pass the file name to Symphony for saving...
                          // if (symphonyConnected) {
                          //   ObjectOutputStream oos = new ObjectOutputStream(symphonySocket.getOutputStream());
                          //   oos.writeObject(fileName);
                          //   oos.close();
                          // }

                          System.out.println("Setting up handshake with Vision software...");
                          // Pipe the data to the Vision program.
                          dataSaver = new RawDataToVision(fileNames, commonPath, header,
                                  nSamplesToBuffer, nBuffers, secondsToStream);
                          inputStream.addSampleListener(dataSaver);
                          System.out.println("Handshake complete!");
                      } catch (IOException ex) {
                          System.err.println("Could not read command.");
                      }
                  }
              };
              labviewThread.start();
            } else {
              System.out.println("Received connection from Symphony...");
              symphonySocket = clientSocket;
              symphonyConnected = true;
            }
        }
    }

}
