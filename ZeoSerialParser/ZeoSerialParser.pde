/*

  Plots EEG spectral power as determined by Zeo, in the style of a strip chart.
  Also parses the Zeo serial stream into human-readable form. Uses an event-driven 
  approach to reading the serial port, which cuts down on CPU usage and catches 
  most frequency messages. Those not caught are due to a 65 byte being both the
  start message indicator as well as part of the data stream. I buffer one value,
  so that freq powers of 0 or 65 can be replaced with their most recent value,
  which keeps the plots pretty. Values saved to disk are as-read, however.
  
  Runs fullscreen on netbook (1024 x 600 px).
  
  Todd Anderson
  Oct 2012
  
  IDEAS
  - allow button press to indicate mental states (focusing, daydreaming, eureka)
    perhaps on dedicated hardware for the hand.
  - Screenshot during high gamma, or maybe at 30 second intervals. Also audio recording?
  - scale bars for each strip
  - interface to switch btw strip and full height plotting

*/

// Flags:
  boolean printBytes = false;
  boolean debugDots = false;
  boolean printHeader = false;
  boolean printTimestamps = false;
  boolean printEvent = true;
  boolean printFreq = true;
  boolean printSleepStage = true;
  boolean toPlot = true;  // use to graph frequency power over time
  boolean toSave = true;
  boolean useOSC = false;

// Colors:
  color deltaColor = color(140, 80, 30);
  color thetaColor = color(200, 180, 20);
  color alphaColor = color(220, 60, 20);
  color beta1Color = color(100, 100, 160);
  color beta2Color = color(0, 20, 160);
  color beta3Color = color(20, 20, 255);
  color gammaColor = color(40, 200, 20);

// Paths:
  String pathHome;
  String asimovName;
  String userName;
  String dataPath = "/LogFiles/";
  String logFolder;
  
// Data buffers:
  int numSamples = 512;
  int[] deltas = new int[numSamples];
  int[] thetas = new int[numSamples];
  int[] alphas = new int[numSamples];
  int[] beta1s = new int[numSamples];
  int[] beta2s = new int[numSamples];
  int[] beta3s = new int[numSamples];
  int[] gammas = new int[numSamples];
  int[] events = new int[numSamples]; // time line of event triggers

// EEG variables:
  int[] freqData = new int[15];
  int interFreqTime;
  long unixTime = 3;
  int eventNum;
  int sleepState;
  int badSignal;
  int sqi;
  int impedance;             
  int delta;
  int theta;
  int alpha;
  int beta1;
  int beta2;
  int beta3;
  int gamma;
  int delta_old;
  int theta_old;
  int alpha_old;
  int beta1_old;
  int beta2_old;
  int beta3_old;
  int gamma_old;
  
// OSC:
  String oscIP = "192.168.1.127"; // address of remote hardware
  int sendPort = 5602; // send message to this port
  int recvPort = 5601; // receive messages on this port
  NetAddress ambisonicAddress;
  OscP5 osc;
  import oscP5.*;
  import netP5.*;
  
// Plotting variables:
  int minEEG = 3000;
  int maxEEG = 6000;
  int gammaMult = 30; // gamma is normally around ~150, far smaller than the others
  int bufferLoc = 0;
  int xW;  
  int markTime = 0;
  int markNum = 0;
  int statusBarH = 30;
  int stripH;
  int bottomChartY; // y coord of lowest chart
  
  // text positioning in X axis...
  PFont fontNorm;
  int offsetTextX = 80;
  int deltaTextX = 10;
  int thetaTextX = deltaTextX + offsetTextX;
  int alphaTextX = thetaTextX + offsetTextX;
  int beta1TextX = alphaTextX + offsetTextX;
  int beta2TextX = beta1TextX + offsetTextX;
  int beta3TextX = beta2TextX + offsetTextX;
  int gammaTextX = beta3TextX + offsetTextX;
  
  // text positioning in Y axis... 
  int offsetTextY = 10;
  int legendY;
  
// Log:
  PrintWriter dataLog;
  PrintWriter sleepLog;
  PrintWriter debugLog;
  
// Serial:
  //import java.util.TimeZone.*;
  String portPrefix = "/dev/tty.usbserial";
  import processing.serial.*;
  int portNum = -1;      // serial port number in list of serial ports
  String[] lines;
  Serial zeo;
  boolean waited = false;  // flag to trigger waiting time on first serial send, since delay() doesn't work in setup
  String curLine = "";
  int oldEventTime = 0;
  int lastFreqTime = 0;
  boolean finishedParsing = true;

// To always run in fullscreen mode, comment out to run in a window.
//boolean sketchFullScreen() {
  //return true;
//}

/*public void init() { 
  frame.removeNotify(); 
  frame.setUndecorated(true); 
  frame.addNotify();
  //frame.setLocation(0, 0);
  //frame.setBackground(new java.awt.Color(0, 0, 0)); // fullscreen background color
  super.init();
}*/

void setup() {
  size(1024, 600);
  //size(300, 300);
  background(0);
  
  frameRate(10); // does bigger number matter with serialEvent?
  
  // Paths:
    pathHome = System.getProperty("user.home"); // gets path to cur user home on any platform
    
    // Read Asimov name
    String[] nameLines = loadStrings(pathHome + "");
    asimovName = "thisComputer";//split(nameLines[0],',')[1];
    println("This Asimov box is called "+asimovName);
    
    // Read current participant name
    userName = "yoav";//split(nameLines[1],',')[1];
    println("Participant is named "+userName);
    
    logFolder = pathHome+"/Documents/";
  
  // OSC:
    if(useOSC) {
      println("connecting to OSC...");
      osc = new OscP5(this, recvPort);
      ambisonicAddress = new NetAddress(oscIP, sendPort);
    }
  
  // Serial:
    println("Serial ports:");
    println(Serial.list());
    int numPorts = Serial.list().length;
    
    // find port based on name
    /*for(int i=0; i<numPorts; i++) {
      String portPath = Serial.list()[i];
      String portName = split(portPath, '/')[2]; 
      println("port name: "+portName);
      if(portName.equals(portPrefix+"0"))
        portNum = i;
      else if(portName.equals(portPrefix+"1"))
        portNum = i;
    }
    if(portNum == -1) {
      println("no serial port with prefix "+portPrefix+" found, please go to Terminal and type:\n sudo chmod a+rw /dev/ttyUSB0");
      exit();
    }*/
    String selectedPortName = Serial.list()[4];
    println("selected port #"+portNum+", aka "+selectedPortName);
    zeo = new Serial(this, selectedPortName, 38400);
    zeo.bufferUntil(65);
    zeo.clear();
  
  // Plotting:
    xW = floor(width / numSamples);
    legendY = height - offsetTextY;
    bottomChartY = height-statusBarH;
    stripH = floor(bottomChartY/7);
  
  // Fonts:
    String fontPath = "Courier-16.vlw";
    fontNorm = loadFont(fontPath);
    println("loading font from: "+fontPath);
    textFont(fontNorm);
    
  // Logs:
    String curDateStr = year()+nf(month(),2)+nf(day(),2);
    String curTimeStr = nf(hour(),2)+"-"+nf(minute(),2)+"-"+nf(second(),2);
    
    String dataFilename = curDateStr+"_"+curTimeStr+"_"+userName+"_ZeoParser_data"+".txt";
    dataLog = createWriter(logFolder + dataFilename);
    println(dataFilename);
    dataLog.println("unixTime,sleepState,delta,theta,alpha,beta1,beta2,beta3,gamma,sqi,badSignal,impedance,interFreqTime");
    
    String sleepFilename = curDateStr+"_"+curTimeStr+"_"+userName+"_ZeoParser_sleeps"+".txt";
    sleepLog = createWriter(logFolder + sleepFilename);
    println(sleepFilename);
    
    String debugLogname = curDateStr+"_"+curTimeStr+"_"+userName+"_SleepSound_debug.txt";
    debugLog = createWriter(logFolder + debugLogname);
    println(debugLogname);
}

void draw() {
  // deal with freq data
    delta = freqData[1]  + 256*freqData[2];
    theta = freqData[3]  + 256*freqData[4];
    alpha = freqData[5]  + 256*freqData[6];
    beta1 = freqData[7]  + 256*freqData[8];
    beta2 = freqData[9]  + 256*freqData[10];
    beta3 = freqData[11] + 256*freqData[12];
    gamma = freqData[13] + 256*freqData[14];
  
  if(printFreq){
    println(interFreqTime+" ms\t unix "+unixTime+"  d "+delta+"  t "+theta+"  a "+alpha+"  b1 "+beta1+"  b2 "+beta2+"  b3 "+beta3+"  g "+gamma+"\t sqi "+sqi+"\t bs "+badSignal);
  }
  
  if(toSave) {
    dataLog.println(unixTime+","+sleepState+","+delta+","+theta+","+alpha+","+beta1+","+beta2+","+beta3+","+gamma+","+sqi+","+badSignal+","+impedance+","+interFreqTime);
  }
  
  if(toPlot) {
    // pave over zeros; ok to replace variables, b/c we already saved & printed
      if(gamma == 0 || gamma == 65) {
        gamma = gamma_old;
      } else {
        gamma_old = gamma;
      }
      
      if(beta3 == 0 || beta3 == 65) {
        beta3 = beta3_old;
      } else {
        beta3_old = beta3;
      }
      
      if(beta2 == 0 || beta2 == 65) {
        beta2 = beta2_old;
      } else {
        beta2_old = beta2;
      }
      
      if(beta1 == 0 || beta1 == 65) {
        beta1 = beta1_old;
      } else {
        beta1_old = beta1;
      }
      
      if(alpha == 0 || alpha == 65) {
        alpha = alpha_old;
      } else {
        alpha_old = alpha;
      }
      
      if(theta == 0 || theta == 65) {
        theta = theta_old;
      } else {
        theta_old = theta;
      }
      
      if(delta == 0 || delta == 65) {
        delta = delta_old;
      } else {
        delta_old = delta;
      }
    
    // fill plot buffers...
      deltas[bufferLoc] = height-int(map(delta, minEEG, maxEEG, bottomChartY-stripH*7, bottomChartY-stripH*6));
      thetas[bufferLoc] = height-int(map(theta, minEEG, maxEEG, bottomChartY-stripH*6, bottomChartY-stripH*5));
      alphas[bufferLoc] = height-int(map(alpha, minEEG, maxEEG, bottomChartY-stripH*5, bottomChartY-stripH*4));
      beta1s[bufferLoc] = height-int(map(beta1, minEEG, maxEEG, bottomChartY-stripH*4, bottomChartY-stripH*3));
      beta2s[bufferLoc] = height-int(map(beta2, minEEG, maxEEG, bottomChartY-stripH*3, bottomChartY-stripH*2));
      beta3s[bufferLoc] = height-int(map(beta3, minEEG, maxEEG, bottomChartY-stripH*2, bottomChartY-stripH*1));
      gammas[bufferLoc] = height-int(map(gamma*gammaMult, minEEG, maxEEG, bottomChartY-stripH*1, bottomChartY-stripH*0));
      if(markTime > 0) {
        events[bufferLoc] = markTime;
        markTime = 0;
      }
      else
        events[bufferLoc] = 0;
      bufferLoc = (bufferLoc+1) % numSamples;
    
    // plot buffers...
      background(0);
      strokeWeight(1);
      int index = (bufferLoc) % numSamples;
      int curX = xW;
      for(int i=1; i<numSamples; i++){
        index = (bufferLoc+i-1) % numSamples;
        curX = i*xW;
        int curX2 = curX+xW;
        stroke(deltaColor);
        line(curX, deltas[index], curX2, deltas[(index+1)%numSamples]);
        stroke(thetaColor);
        line(curX, thetas[index], curX2, thetas[(index+1)%numSamples]);
        stroke(alphaColor);
        line(curX, alphas[index], curX2, alphas[(index+1)%numSamples]);
        stroke(beta1Color);
        line(curX, beta1s[index], curX2, beta1s[(index+1)%numSamples]);
        stroke(beta2Color);
        line(curX, beta2s[index], curX2, beta2s[(index+1)%numSamples]);
        stroke(beta3Color);
        line(curX, beta3s[index], curX2, beta3s[(index+1)%numSamples]);
        stroke(gammaColor);
        line(curX, gammas[index], curX2, gammas[(index+1)%numSamples]);
        if(events[index] > 0) {
          stroke(255, 70);
          line(curX, 0, curX, height);
          fill(255, 70);
          textAlign(RIGHT, TOP);
          text(nf((millis()-events[index])/60000.0,0,2)+"m", curX, 10);
        }
      }
    
    // freq labels...
      textAlign(LEFT, BASELINE);
      fill(deltaColor);
      text("delta", deltaTextX, legendY);
      fill(thetaColor);
      text("theta", thetaTextX, legendY);
      fill(alphaColor);
      text("alpha", alphaTextX, legendY);
      fill(beta1Color);
      text("beta1", beta1TextX, legendY);
      fill(beta2Color);
      text("beta2", beta2TextX, legendY);
      fill(beta3Color);
      text("beta3", beta3TextX, legendY);
      fill(gammaColor);
      text("gamma", gammaTextX, legendY);
    
    // write current sleep label...
      fill(100);
      textAlign(RIGHT, BASELINE);
      text(matchSleepNumToName(sleepState), width-10, legendY);
  }
    
  if(useOSC) {
    int[] freqs = new int[8];
    freqs[0] = delta;
    freqs[1] = theta;
    freqs[2] = alpha;
    freqs[3] = beta1;
    freqs[4] = beta2;
    freqs[5] = beta3;
    freqs[6] = gamma;
    freqs[7] = sqi;
    
    OscMessage brainMessage = new OscMessage("/eeg/freqs");
    brainMessage.add(freqs);
    osc.send(brainMessage, ambisonicAddress);
  }
  
  noLoop();
}

// returns number of bytes in data payload.
int readHeader(int[] header) {
  
  // calculate size of the data payload...
  int dataSize = (( header[3] * 256 ) + header[2]);
  
  if(printHeader){
    print("Version: ");
    print(header[0]);
    
    print(" Checksum: ");
    print(header[1]);
    
    print(" Size: ");
    print(header[3]);
    print(" ");
    print(header[2]);
    print(" ");
    print(dataSize);
    
    print(" Size(inv): ");
    print(header[5]);
    print(" ");
    print(header[4]);
    
    print(" Timestamp: ");
    print(header[6]);
    print(" Subsec: ");
    print(header[8]);
    print(" ");
    print(header[7]);
    
    print(" SeqNr: ");
    print(header[9]);
    println("");
  }
  
  // delete this if you want the complete waveform data, but I think the buffer is too small!
  if ( dataSize > 20 ) {
    dataSize = 1;
    zeo.clear();
  }
  
  // make sure size matches inverse size...
  if ( header[3]+header[5] == 255 & header[2]+header[4] == 255 ) { 
    // if matches, parse the data:
    //readData(dataSize);
    return dataSize;
  } 
  else {
    //if (printDebug)
    println("Header lengths mismatched");
    zeo.clear();
    finishedParsing = true;
    return -1;
  }
}

void parseDataLine(int[] data) {
  
  int id = data[0];
  //println("id: "+id);
  
  // extract timestamp...
  if(id == 138){
    int[] timestamp = new int[4];
    timestamp[0] = data[1];
    timestamp[1] = data[2];
    timestamp[2] = data[3];
    timestamp[3] = data[4];
    unixTime = timestamp[0] + (timestamp[1] << 8) + (timestamp[2] << 16) + (timestamp[3] << 24); // LSB
    if (printTimestamps)
      println("unixtime: "+unixTime);
  }
  
  // Extract Fourier powers; 131 = 0x83 in hex:
  else if ( id == 131 ) {
    int now = millis();
    interFreqTime = now-lastFreqTime;
    //print(+" ms  ");
    lastFreqTime = now;
    
    freqData = data;
    
    loop();
  }
  
  // Signal Quality Index dataType, from 0-30.  0x84 in hex = 132 in dec:
  else if ( id == 132 ){
    sqi = data[1];
    //if (sqi < 27)
      //println("SQI: "+sqi);
  }
  
  // Impedance (at where?)
  else if ( id == 151 ){
    impedance = data[1];
    //println("impedance: "+impedance);
  }
  
  // get signal on/off...
  else if (id == 156) {
    badSignal = data[1]; // 0 is good, 1 is bad
    //if (badSignal == 1)
      //println("bad signal indicator is "+badSignal);
  }
  
  // get sleep phase number...
  else if (id == 157) {
    sleepState = data[1];
    println("sleep state is "+sleepState);
    
    // log:
    String curDateStr = year()+nf(month(),2)+nf(day(),2);
    String curTimeStr = nf(hour(),2)+"-"+nf(minute(),2)+"-"+nf(second(),2);
    sleepLog.println(curDateStr+"_"+curTimeStr+","+sleepState);
    
    // flush both data files
    sleepLog.flush();
    dataLog.flush();
    debug.flush();
  }
  
  // parse Event messages...
  else if(id == 0) {
    eventNum = data[1];
    if(printEvent){
      if (eventNum == 5)  { println(" NightStart "); }
      if (eventNum == 7)  { println(" SleepOnset "); }
      if (eventNum == 14) { println(" HeadbandDocked "); }
      if (eventNum == 15) { println(" HeadbandUnDocked "); }
      if (eventNum == 16) { println(" AlarmOff "); }
      if (eventNum == 17) { println(" AlarmSnooze "); }
      if (eventNum == 19) { println(" AlarmPlay "); }
      if (eventNum == 21) { println(" NightEnd "); }
      if (eventNum == 36) { println(" NewHeadband "); }
      //println();
    }
  }
  
  // get waveform...
  //else if(id == 128)
  
  else {
    //println("not parsing id "+id+": ");
  }
  
  //println("f");
  finishedParsing = true;
  //zeo.clear();
}

String matchSleepNumToName(int sleepState) {
  String sleepStateName = "";
  if(sleepState == 0)
    sleepStateName = "No Data";
  else if(sleepState == 1)
    sleepStateName = "Awake";
  else if(sleepState == 2)
    sleepStateName = "REM";
  else if(sleepState == 3)
    sleepStateName = "Light";
  else if(sleepState == 4)
    sleepStateName = "Deep";
  else
    sleepStateName = "Unknown";
  return sleepStateName;
}

void keyPressed() {
  switch(key) {
    case 'm':
      // writes event signal to log file, need to note what event means seperately
      markTime = millis();
      markNum++;
      String curDateStr = year()+nf(month(),2)+nf(day(),2);
      String curTimeStr = nf(hour(),2)+"-"+nf(minute(),2)+"-"+nf(second(),2);
      println("event number "+markNum);
      debugLog.println(curDateStr+"_"+curTimeStr+",event,"+markNum+","+markTime);
      break;
    case ';':
      maxEEG+=500;
      println("max EEG plot: "+maxEEG);
      break;
    case '\'':
      maxEEG-=500;
      println("max EEG plot: "+maxEEG);
      break;
    case '.':
      minEEG+=500;
      println("min EEG plot: "+minEEG);
      break;
    case '/':
      minEEG-=500;
      println("min EEG plot: "+minEEG);
      break;
    case 'r':
      println("reset serial");
      zeo.clear();
      break;
    case 'q':
      println("stopping...");
      dataLog.flush();
      dataLog.close();
      sleepLog.flush();
      sleepLog.close();
      debugLog.flush();
      debugLog.close();
      zeo.clear();
      zeo.stop();
      stop();
      exit();
      println(" finished.");
      break;
    default:
      curDateStr = year()+nf(month(),2)+nf(day(),2);
      curTimeStr = nf(hour(),2)+"-"+nf(minute(),2)+"-"+nf(second(),2);
      println("pressed key:"+key);
      debugLog.println(curDateStr+"_"+curTimeStr+",key,"+key);
      break;
  }
}

int[] printBytes(byte[] b) {
  int[] dataLog = new int[b.length];
  for(int i=0; i<b.length; i++) {
    int ib = b[i] & 0xFF;
    dataLog[i] = ib;
    if(printBytes)
      print(ib+" ");
  }
  if(printBytes)
    println();
  return dataLog;
}

// Notes on serial event parsing:
  // TODO if another 65 comes in, the stream gets cutoff. Flag to ignore 'A"s?
  // why do 65's appear in freq data (too low, except for gamma)? two bytes per bin
  // why do 65's only appear after header mismatch? I think serialEvent oblitirated the buffer
  // how many header mismatches are expected?
  // why is 65 triggering the erasing of freqData? not sure; deep copy?
  // turn off bufferUntil? Doesn't work for '', "", or 256 or 1000.
void serialEvent(Serial p) {
  //int newByte = p.read();
  //if(newByte == 52) {
  byte[] header = new byte[10];
  int numBytes = p.readBytes(header);
  //println("numBytes: "+numBytes);
  // TODO avoid converting byte[] to int[]
  if(printBytes)
    print("h  ");
  int dataSize = readHeader(printBytes(header));
  if(dataSize > 0) {
    byte[] data = new byte[dataSize+1];
    numBytes = p.readBytes(data);
    if(printBytes)
      print("d  ");
    parseDataLine(printBytes(data));
  }
  p.clear();
  
  /*else {
    int eventTime = millis();
    print((eventTime-oldEventTime)+" ");
    oldEventTime = eventTime;
  }*/
  
}

