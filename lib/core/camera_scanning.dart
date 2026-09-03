import 'dart:io';
import 'dart:ui' show Rect;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../core/database.dart';
import '../core/image_processor_service.dart';

class DebugFrameInfo {
  final List<Rect> blockBoxes;
  final Rect? unionBox;
  final int effectiveWidth;
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
  final FramePositionAnalyzer _positionAnalyzer =
  FramePositionAnalyzer();

  // ================================================================
  // VOICE GUIDANCE
  // ================================================================

  final FlutterTts _tts = FlutterTts();

  bool _voiceGuidanceEnabled = false;

  bool get voiceGuidanceEnabled =>
      _voiceGuidanceEnabled;

  /// Enable or disable the app's own voice guidance.
  ///
  /// Voice Guidance is separate from Android TalkBack / iOS VoiceOver.
  Future<void> setVoiceGuidance(bool enabled) async {
    _voiceGuidanceEnabled = enabled;

    if (!enabled) {
      // Stop any speech currently being played.
      await _tts.stop();
      return;
    }

    await _configureTts();
  }

  Future<void> _configureTts() async {
    await _tts.setLanguage('en-US');

    // Slightly slower than normal speech so instructions
    // are easier to understand.
    await _tts.setSpeechRate(0.45);

    await _tts.setVolume(1.0);

    await _tts.setPitch(1.0);
  }

  Future<void> _speak(String message) async {
    if (!_voiceGuidanceEnabled) {
      return;
    }

    try {
      // Stop previous announcement before speaking the new one.
      await _tts.stop();

      await _tts.speak(message);
    } catch (e) {
      debugPrint(
        'Voice Guidance error: $e',
      );
    }
  }

  // ================================================================
  // SCANNING STATE
  // ================================================================

  bool _liveScanningActive = true;

  bool get isLiveScanningActive =>
      _liveScanningActive;

  final void Function(DebugFrameInfo? frame)?
  onDebugFrame;

  DateTime _lastLiveAnalysis =
  DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _liveAnalysisInterval =
  Duration(milliseconds: 400);

  // Prevent repeatedly saying:
  // "Medication is ready. Tap to scan."
  bool _hasAnnouncedReady = false;

  // ================================================================
  // CALLBACKS
  // ================================================================

  final Function(String) onStatusUpdated;
  final Function(String) onWarningTriggered;
  final VoidCallback onCameraInitialized;

  ScannerController({
    required this.onStatusUpdated,
    required this.onWarningTriggered,
    required this.onCameraInitialized,
    this.onDebugFrame,
  });

  // ================================================================
  // START SCAN
  // ================================================================

  void captureNext() {
    if (!_liveScanningActive) {
      return;
    }

    _captureNextFrame = true;

    _hasAnnouncedReady = false;

    onStatusUpdated(
      "Scanning...",
    );

    _speak(
      "Scanning medication. Please hold the medication steady.",
    );
  }

  // ================================================================
  // SCAN AGAIN
  // ================================================================

  void resumeLiveScanning() {
    _liveScanningActive = true;

    _hasAnnouncedReady = false;

    onStatusUpdated(
      "Point the camera at a label to scan.",
    );

    _speak(
      "Point the camera at a medication label to scan.",
    );
  }

  // ================================================================
  // DISPOSE
  // ================================================================

  Future<void> dispose() async {
    await _tts.stop();
    await cameraController?.dispose();
  }

  // ================================================================
  // CAMERA INITIALIZATION
  // ================================================================

  Future<void> initializeCamera() async {
    List<CameraDescription> cameras =
    await availableCameras();

    if (cameras.isNotEmpty) {
      cameraController = CameraController(
        cameras.first,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup:
        Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await cameraController?.initialize();

      await cameraController?.setFocusMode(
        FocusMode.auto,
      );

      onCameraInitialized();

      cameraController?.startImageStream(
            (CameraImage image) async {
          final bool shouldCaptureForSave =
              _liveScanningActive &&
                  _captureNextFrame;

          final bool shouldAnalyzeLive =
              _liveScanningActive &&
                  DateTime.now().difference(
                    _lastLiveAnalysis,
                  ) >=
                      _liveAnalysisInterval;

          if (!shouldCaptureForSave &&
              !shouldAnalyzeLive) {
            return;
          }

          if (shouldCaptureForSave) {
            _captureNextFrame = false;
          }

          if (shouldAnalyzeLive) {
            _lastLiveAnalysis =
                DateTime.now();
          }

          try {
            // ======================================================
            // CONVERT CAMERA IMAGE
            // ======================================================

            final WriteBuffer allBytes =
            WriteBuffer();

            for (final Plane plane
            in image.planes) {
              allBytes.putUint8List(
                plane.bytes,
              );
            }

            final Uint8List rawBytes =
            allBytes
                .done()
                .buffer
                .asUint8List();

            final bool isAndroid =
                Platform.isAndroid;

            final int sensorOrientation =
                cameraController!
                    .description
                    .sensorOrientation;

            // ======================================================
            // OCR
            // ======================================================

            final RecognizedText RTresult =
            await _ocrService.scanLabel(
              rawBytes,
              image.width,
              image.height,
              isAndroid,
              sensorOrientation,
            );

            // ======================================================
            // POSITION ANALYSIS
            // ======================================================

            final bool swapDims =
                sensorOrientation == 90 ||
                    sensorOrientation == 270;

            final int effectiveWidth =
            swapDims
                ? image.height
                : image.width;

            final int effectiveHeight =
            swapDims
                ? image.width
                : image.height;

            final PositionFeedback
            positionFeedback =
            _positionAnalyzer.analyze(
              RTresult,
              effectiveWidth,
              effectiveHeight,
            );

            // ======================================================
            // DEBUG FRAME
            // ======================================================

            if (onDebugFrame != null) {
              onDebugFrame!(
                DebugFrameInfo(
                  blockBoxes: RTresult
                      .blocks
                      .map(
                        (b) => b.boundingBox,
                  )
                      .toList(),
                  unionBox:
                  positionFeedback
                      .boundingBox,
                  effectiveWidth:
                  effectiveWidth,
                  effectiveHeight:
                  effectiveHeight,
                  isWellPositioned:
                  positionFeedback
                      .isWellPositioned,
                  feedbackMessage:
                  positionFeedback
                      .message,
                  areaRatio:
                  positionFeedback
                      .areaRatio,
                  offsetXRatio:
                  positionFeedback
                      .offsetXRatio,
                  offsetYRatio:
                  positionFeedback
                      .offsetYRatio,
                ),
              );
            }

            // ======================================================
            // MEDICATION NOT WELL POSITIONED
            // ======================================================

            if (!positionFeedback
                .isWellPositioned) {
              if (shouldCaptureForSave ||
                  _liveScanningActive) {
                onStatusUpdated(
                  positionFeedback.message,
                );
              }

              return;
            }

            // ======================================================
            // MEDICATION IS WELL POSITIONED
            // ======================================================

            if (!shouldCaptureForSave) {
              onStatusUpdated(
                "${positionFeedback.message} Tap to scan.",
              );

              // Only say this once rather than every 400ms.
              if (!_hasAnnouncedReady) {
                _hasAnnouncedReady = true;

                _speak(
                  "Medication is positioned correctly. Tap scan to capture it.",
                );
              }

              return;
            }

            // ======================================================
            // CAPTURED
            // ======================================================

            _liveScanningActive = false;

            final String result =
                RTresult.text;

            final String medTitle =
            _titleExtract.extractTitle(
              RTresult,
            );

            _lastScannedText = result;

            // ======================================================
            // DATABASE LOGIC
            // ======================================================

            if (medTitle.isNotEmpty) {
              final recentScans =
              await _dbService
                  .outPutLabels(
                whereArgs: [medTitle],
                whereClause: 'text = ?',
                orderBy: 'id DESC',
                limitCount: 1,
              );

              bool warningFlag = false;

              if (recentScans.isNotEmpty) {
                final lastScanTime =
                DateTime.parse(
                  recentScans.first.times,
                );

                final timeDifference =
                DateTime.now().difference(
                  lastScanTime,
                );

                if (timeDifference.inHours <
                    4) {
                  warningFlag = true;
                }
              }

              // ====================================================
              // DUPLICATE MEDICATION
              // ====================================================

              if (warningFlag) {
                onStatusUpdated(
                  "Warning: '$medTitle' recently scanned.\n\n"
                      "Label text:\n$_lastScannedText",
                );

                _speak(
                  "Warning. $medTitle was recently scanned.",
                );

                onWarningTriggered(
                  medTitle,
                );
              }

              // ====================================================
              // NEW MEDICATION
              // ====================================================

              else {
                final newScan =
                ScannedLabels(
                  text: medTitle,
                  times: DateTime.now()
                      .toIso8601String(),
                );

                await _dbService
                    .insertLabels(
                  newScan,
                );

                onStatusUpdated(
                  "Saved '$medTitle' to database.\n\n"
                      "Label text:\n$_lastScannedText",
                );

                _speak(
                  "Medication identified as $medTitle. "
                      "The medication has been saved.",
                );
              }
            }

            // ======================================================
            // NO TITLE FOUND
            // ======================================================

            else {
              if (result.isEmpty) {
                onStatusUpdated(
                  "No text found.",
                );

                _speak(
                  "No medication text was found. Please try again.",
                );
              } else {
                onStatusUpdated(
                  result,
                );

                _speak(
                  "Medication text identified.",
                );
              }
            }
          }

          // ========================================================
          // ERROR HANDLING
          // ========================================================

          catch (e) {
            final bool isBlurry =
            e.toString().contains(
              "BLURRY_FRAME",
            );

            if (shouldCaptureForSave) {
              if (isBlurry) {
                onStatusUpdated(
                  "Too blurry. Please hold still.",
                );

                HapticFeedback.vibrate();

                _speak(
                  "The image is too blurry. "
                      "Please hold the medication steady and try again.",
                );
              } else {
                onStatusUpdated(
                  "Error: $e",
                );

                _speak(
                  "The medication could not be scanned. "
                      "Please try again.",
                );
              }
            }

            else if (isBlurry) {
              onStatusUpdated(
                "Too blurry to preview. Hold steady.",
              );
            }

            if (onDebugFrame != null) {
              onDebugFrame!(null);
            }
          }
        },
      );
    }
  }

  // ================================================================
  // FORCE SAVE
  // ================================================================

  Future<void> forceSaveLabel(
      String medTitle,
      ) async {
    final forcedScan =
    ScannedLabels(
      text: medTitle,
      times: DateTime.now()
          .toIso8601String(),
    );

    await _dbService.insertLabels(
      forcedScan,
    );

    onStatusUpdated(
      "Forced save for '$medTitle'.\n\n"
          "Label text:\n$_lastScannedText",
    );

    _speak(
      "$medTitle has been saved.",
    );
  }
}