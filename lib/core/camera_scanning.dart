import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:ui' show Rect; 
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../core/image_processor_service.dart';
import '../core/database.dart';


class DebugFrameInfo { 
  final List<Rect> blockBoxes;  // one box per detected text block, for the thin per-line outlines
  final Rect? unionBox; // the box FramePositionAnalyzer actually judges against the thresholds
  final int effectiveWidth;  //coordinate space the boxes above are in
  final int effectiveHeight; 
  final bool isWellPositioned; 
  final String feedbackMessage; 
  final double? areaRatio; 
  final double? offsetXRatio; 
  final double? offsetYRatio; 

  const DebugFrameInfo({ 
    required this.blockBoxes, 
    required this.unionBox, 
    required this.effectiveWidth, 
    required this.effectiveHeight, 
    required this.isWellPositioned, 
    required this.feedbackMessage, 
    this.areaRatio, 
    this.offsetXRatio, 
    this.offsetYRatio, 
  }); 
} 

class ScannerController {
  CameraController? cameraController;
  bool _captureNextFrame = false;
  String _lastScannedText = "";

  final OCRProcess _ocrService = OCRProcess();
  final DatabaseService _dbService = DatabaseService();
  final TitleExtraction _titleExtract = TitleExtraction();
  final FramePositionAnalyzer _positionAnalyzer = FramePositionAnalyzer(); 

  bool _liveScanningActive = true;        //true to start the program to live scans when the program starts
  bool get isLiveScanningActive => _liveScanningActive;     

  
  final void Function(DebugFrameInfo? frame)? onDebugFrame; //called with null to clear the overlay on a failed/blurry frame
  DateTime _lastLiveAnalysis = DateTime.fromMillisecondsSinceEpoch(0);      //initalizing to the earliest date possible
  static const Duration _liveAnalysisInterval = Duration(milliseconds: 400); // ~2.5 analyses/sec of live guidance; can raise this if its heavy on battery

  // Callbacks to communicate with the UI
  final Function(String) onStatusUpdated;
  final Function(String) onWarningTriggered;
  final VoidCallback onCameraInitialized;
  
  ScannerController({
    required this.onStatusUpdated,
    required this.onWarningTriggered,
    required this.onCameraInitialized,
    this.onDebugFrame, 
  });

  // Call this from the UI when the button is pressed
  void captureNext() {
    if (!_liveScanningActive) return; //ignore taps while a previous result is on screen, call resumeLiveScanning() first
    _captureNextFrame = true;
    onStatusUpdated("Scanning...");
  }

  // Call this function when user hits "scan again" button.
  void resumeLiveScanning() {
    _liveScanningActive = true;
    onStatusUpdated("Point the camera at a label to scan."); 
  } 

  // Call this when the UI is closed
  void dispose() {
    cameraController?.dispose();
  }

 
  Future<void> initializeCamera() async {
    List<CameraDescription> cameras = await availableCameras();
    if (cameras.isNotEmpty) {             //check if device have cameras
      cameraController = CameraController(
        cameras.first,             // first because backcamera
        ResolutionPreset.max, 
        enableAudio: false,       // turn off microphone 
        imageFormatGroup: Platform.isAndroid 
            ? ImageFormatGroup.yuv420         //if andriod hardcode to change format into yuv420
            : ImageFormatGroup.bgra8888,      //if ios hardcode to change format into BGRA8888
      );
      await cameraController?.initialize();
      await cameraController?.setFocusMode(FocusMode.auto);

      onCameraInitialized();
      
      cameraController?.startImageStream((CameraImage image) async {
          final bool shouldCaptureForSave = _liveScanningActive && _captureNextFrame;  //safeguard to prevents _captureNextFrame from remaining true causing a save
          final bool shouldAnalyzeLive = _liveScanningActive && DateTime.now().difference(_lastLiveAnalysis) >= _liveAnalysisInterval; //has 400ms passed since last analysis

          if (!shouldCaptureForSave && !shouldAnalyzeLive) { 
            return;       // both are false means ignore and go next frame
          }
          if (shouldCaptureForSave) _captureNextFrame = false;      //stops capturing another frame
          if (shouldAnalyzeLive) _lastLiveAnalysis = DateTime.now();  //reset timer of last analysis
          try {
            // --- THE MEMORY FLATTENER ---
            final WriteBuffer allBytes = WriteBuffer();
            for (final Plane plane in image.planes) {
              allBytes.putUint8List(plane.bytes);
            }
            final Uint8List rawBytes = allBytes.done().buffer.asUint8List();
            
            final bool isAndroid = Platform.isAndroid;
            final int sensorOrientation = cameraController!.description.sensorOrientation; //give your phone camera orientation
            
            // --- FEED THE ENGINE ---
            //basically feed the scanned text stream frm camera into google ML kit and get back RTresult (RecognizedTextResults)
            final RecognizedText RTresult = await _ocrService.scanLabel(rawBytes, image.width, image.height, isAndroid,sensorOrientation);

            
            // ML Kit reports bounding boxes relative to the "upright" image,
            // so if the sensor is rotated 90/270 degrees we need to swap
            // width/height to match before doing any position math.
            final bool swapDims = sensorOrientation == 90 || sensorOrientation == 270; 
            final int effectiveWidth = swapDims ? image.height : image.width; 
            final int effectiveHeight = swapDims ? image.width : image.height; 

            final PositionFeedback positionFeedback = 
                _positionAnalyzer.analyze(RTresult, effectiveWidth, effectiveHeight); 

            if (onDebugFrame != null) { 
              onDebugFrame!(DebugFrameInfo( 
                blockBoxes: 
                    RTresult.blocks.map((b) => b.boundingBox).toList(), 
                unionBox: positionFeedback.boundingBox, 
                effectiveWidth: effectiveWidth, 
                effectiveHeight: effectiveHeight, 
                isWellPositioned: positionFeedback.isWellPositioned, 
                feedbackMessage: positionFeedback.message, 
                areaRatio: positionFeedback.areaRatio, 
                offsetXRatio: positionFeedback.offsetXRatio, 
                offsetYRatio: positionFeedback.offsetYRatio, 
              )); 
            } 

            if (!positionFeedback.isWellPositioned) { //checks if frame is well position or not, if not then tell user how to fix
              if (shouldCaptureForSave || _liveScanningActive) {  //this prevents a bug where "Is well position" text replaces the result text
                onStatusUpdated(positionFeedback.message);
              }
              return;
            }

            if (!shouldCaptureForSave) { //tells user, is well frame and user can scan and frames get discarded and waits for new one
              onStatusUpdated("${positionFeedback.message} Tap to scan."); 
              return; 
            } 

            _liveScanningActive = false;  //stops live scanning flag

            final String result = RTresult.text;      //covert the RTRESULT into a string format
            final String medTitle = _titleExtract.extractTitle(RTresult);  //this one uses the RTresult to feed into titleExtract function so we can extract the biggest lines text from the scanned image
            _lastScannedText = result;

            //Database logic
            if (medTitle.isNotEmpty) {
            final recentScans = await _dbService.outPutLabels(
              whereArgs: [medTitle],
              whereClause: 'text = ?',
              orderBy: 'id DESC', 
              limitCount: 1
            );
            
            bool warningFlag = false;

            if (recentScans.isNotEmpty) {
              final lastScanTime = DateTime.parse(recentScans.first.times);  
              final timeDifference = DateTime.now().difference(lastScanTime); 

              if (timeDifference.inHours < 4) { 
                warningFlag = true;
              }
            }

            if (warningFlag) {
              onStatusUpdated("Warning: '$medTitle' recently scanned.\n\nLabel text:\n$_lastScannedText");
              // Trigger the warning dialog in the UI
              onWarningTriggered(medTitle);
            } else {
              final newScan = ScannedLabels(text: medTitle, times: DateTime.now().toIso8601String());
              await _dbService.insertLabels(newScan);
              
              // Now it shows the success message AND the full text it read below it.
              onStatusUpdated("Saved '$medTitle' to database.\n\nLabel text:\n$_lastScannedText");
            }
          } else {
            // Update the UI with the raw text if no title was found
            onStatusUpdated(result.isEmpty ? "No text found." : result);
          }

          } catch (e) {
            
            final bool isBlurry = e.toString().contains("BLURRY_FRAME"); 
            if (shouldCaptureForSave) { 
              if (isBlurry) {
                onStatusUpdated("Too blurry. Please hold still.");
                HapticFeedback.vibrate();
              } else {
                onStatusUpdated("Error: $e");
              }
            } else if (isBlurry) { 
              onStatusUpdated("Too blurry to preview. Hold steady."); 
            }
            if (onDebugFrame != null) onDebugFrame!(null); 
          }
        });
      }
    }

// The UI can call this directly if the user clicks "Log Anyway"
  Future<void> forceSaveLabel(String medTitle) async {
    final forcedScan = ScannedLabels(text: medTitle, times: DateTime.now().toIso8601String());
    await _dbService.insertLabels(forcedScan);
    onStatusUpdated("Forced save for '$medTitle'.\n\nLabel text:\n$_lastScannedText");
  }
}