import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../core/image_processor_service.dart';
import '../core/database.dart';

class ScannerController {
  CameraController? cameraController;
  bool _captureNextFrame = false;
  String _lastScannedText = "";

  final OCRProcess _ocrService = OCRProcess();
  final DatabaseService _dbService = DatabaseService();
  final TitleExtraction _titleExtract = TitleExtraction();

  // Callbacks to communicate with the UI
  final Function(String) onStatusUpdated;
  final Function(String) onWarningTriggered;
  final VoidCallback onCameraInitialized;
  
  ScannerController({
    required this.onStatusUpdated,
    required this.onWarningTriggered,
    required this.onCameraInitialized,
  });

  // Call this from the UI when the button is pressed
  void captureNext() {
    _captureNextFrame = true;
    onStatusUpdated("Scanning...");
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
          //deleting the current captured frame to get next frame
          if (!_captureNextFrame) {
            return;
          } 
          //stop from capturing next frame
          _captureNextFrame = false;
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
            if (e.toString().contains("BLURRY_FRAME")) {
              onStatusUpdated("Too blurry. Please hold still.");
              HapticFeedback.vibrate();
            } else {
              onStatusUpdated("Error: $e");
            }
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