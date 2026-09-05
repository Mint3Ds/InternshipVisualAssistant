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

/// Information returned after a successful scan.
class MedicationScanResult {
  final String medicationName;
  final String labelText;
  final bool saved;
  final bool duplicate;

  const MedicationScanResult({
    required this.medicationName,
    required this.labelText,
    required this.saved,
    required this.duplicate,
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

  final FlutterTts _tts = FlutterTts();

  bool _voiceGuidanceEnabled = false;

  bool _isSpeaking = false;
  String? _pendingMessage;

  bool get voiceGuidanceEnabled => _voiceGuidanceEnabled;

  Future<void> setVoiceGuidance(bool enabled) async {
    _voiceGuidanceEnabled = enabled;

    if (!enabled) {
      await _tts.stop();
      _isSpeaking = false;
      _pendingMessage = null;
      return;
    }

    await _configureTts();
  }

  Future<void> _configureTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> speak(String message) async {
    await _speak(message);
  }

  Future<void> _speak(String message) async {
    if (!_voiceGuidanceEnabled) {
      debugPrint(
        'TTS disabled. Skipping: $message',
      );
      return;
    }

    try {
      if (_isSpeaking) {
        _pendingMessage = message;
        return;
      }

      _isSpeaking = true;
      _pendingMessage = null;

      await Future.delayed(
        const Duration(milliseconds: 150),
      );

      await _tts.stop();

      await _tts.speak(message);

      // Give Flutter TTS time to finish.
      await Future.delayed(
        const Duration(seconds: 4),
      );

      _isSpeaking = false;

      if (_pendingMessage != null) {
        final nextMessage = _pendingMessage;
        _pendingMessage = null;

        if (nextMessage != null) {
          await _speak(nextMessage);
        }
      }
    } catch (e) {
      debugPrint(
        'Voice Guidance error: $e',
      );

      _isSpeaking = false;
      _pendingMessage = null;
    }
  }

  bool _liveScanningActive = true;

  bool get isLiveScanningActive =>
      _liveScanningActive;

  final void Function(DebugFrameInfo? frame)? onDebugFrame;

  final void Function(MedicationScanResult result)?
  onMedicationScanned;

  DateTime _lastLiveAnalysis =
  DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _liveAnalysisInterval =
  Duration(milliseconds: 400);

  bool _hasAnnouncedReady = false;

  final Function(String) onStatusUpdated;

  final Function(String) onWarningTriggered;

  final VoidCallback onCameraInitialized;

  ScannerController({
    required this.onStatusUpdated,
    required this.onWarningTriggered,
    required this.onCameraInitialized,
    this.onDebugFrame,
    this.onMedicationScanned,
  });

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
  void resumeLiveScanning() {
    _liveScanningActive = true;
    _captureNextFrame = false;
    _hasAnnouncedReady = false;

    onStatusUpdated(
      "Point the camera at a medication label to scan.",
    );

    _speak(
      "Point the camera at a medication label to scan.",
    );
  }

  Future<void> dispose() async {
    await _tts.stop();
    await cameraController?.dispose();
  }

  Future<void> initializeCamera() async {
    final List<CameraDescription> cameras =
    await availableCameras();

    if (cameras.isEmpty) {
      onStatusUpdated(
        "No camera was found.",
      );
      return;
    }

    cameraController = CameraController(
      cameras.first,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    await cameraController?.initialize();

    await cameraController?.setFocusMode(
      FocusMode.auto,
    );

    onCameraInitialized();

    await cameraController?.startImageStream(
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
          _lastLiveAnalysis = DateTime.now();
        }

        try {

          final WriteBuffer allBytes =
          WriteBuffer();

          for (final Plane plane in image.planes) {
            allBytes.putUint8List(
              plane.bytes,
            );
          }

          final Uint8List rawBytes =
          allBytes.done().buffer.asUint8List();

          final bool isAndroid =
              Platform.isAndroid;

          final int sensorOrientation =
              cameraController!
                  .description
                  .sensorOrientation;

          final RecognizedText recognizedText =
          await _ocrService.scanLabel(
            rawBytes,
            image.width,
            image.height,
            isAndroid,
            sensorOrientation,
          );



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

          final PositionFeedback positionFeedback =
          _positionAnalyzer.analyze(
            recognizedText,
            effectiveWidth,
            effectiveHeight,
          );

          if (onDebugFrame != null) {
            onDebugFrame!(
              DebugFrameInfo(
                blockBoxes: recognizedText.blocks
                    .map(
                      (block) =>
                  block.boundingBox,
                )
                    .toList(),
                unionBox:
                positionFeedback.boundingBox,
                effectiveWidth:
                effectiveWidth,
                effectiveHeight:
                effectiveHeight,
                isWellPositioned:
                positionFeedback
                    .isWellPositioned,
                feedbackMessage:
                positionFeedback.message,
                areaRatio:
                positionFeedback.areaRatio,
                offsetXRatio:
                positionFeedback.offsetXRatio,
                offsetYRatio:
                positionFeedback.offsetYRatio,
              ),
            );
          }

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


          if (!shouldCaptureForSave) {
            onStatusUpdated(
              "${positionFeedback.message} Tap to scan.",
            );

            if (!_hasAnnouncedReady) {
              _hasAnnouncedReady = true;

              _speak(
                "Medication is positioned correctly. Tap scan to capture it.",
              );
            }

            return;
          }

          _liveScanningActive = false;

          final String result =
          recognizedText.text.trim();

          final String medTitle =
          _titleExtract
              .extractTitle(
            recognizedText,
          )
              .trim();

          _lastScannedText = result;

          if (result.isEmpty) {
            onStatusUpdated(
              "No text found.",
            );

            onMedicationScanned?.call(
              const MedicationScanResult(
                medicationName:
                "Unknown medication",
                labelText:
                "No readable text was found.",
                saved: false,
                duplicate: false,
              ),
            );

            await _speak(
              "No medication text was found. Please try again.",
            );

            return;
          }

          if (medTitle.isEmpty) {
            onStatusUpdated(
              "Medication name could not be identified.\n\n"
                  "Label text:\n$result",
            );

            onMedicationScanned?.call(
              MedicationScanResult(
                medicationName:
                "Medication name not identified",
                labelText: result,
                saved: false,
                duplicate: false,
              ),
            );

            await _speak(
              "I could not identify the medication name. "
                  "The text I scanned says: $result",
            );

            return;
          }

          final recentScans =
          await _dbService.outPutLabels(
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
            DateTime.now()
                .difference(lastScanTime);

            if (timeDifference.inHours < 4) {
              warningFlag = true;
            }
          }

          if (warningFlag) {
            onStatusUpdated(
              "This medication was recently scanned.",
            );

            onMedicationScanned?.call(
              MedicationScanResult(
                medicationName: medTitle,
                labelText: result,
                saved: false,
                duplicate: true,
              ),
            );

            await _speak(
              "Warning. "
                  "$medTitle was recently scanned. "
                  "The label says: $result",
            );

            await Future.delayed(
              const Duration(milliseconds: 500),
            );

            onWarningTriggered(
              medTitle,
            );

            return;
          }

          final newScan = ScannedLabels(
            text: medTitle,
            times:
            DateTime.now().toIso8601String(),
          );

          await _dbService.insertLabels(
            newScan,
          );

          onStatusUpdated(
            "Medication identified.",
          );

          onMedicationScanned?.call(
            MedicationScanResult(
              medicationName: medTitle,
              labelText: result,
              saved: true,
              duplicate: false,
            ),
          );

          // Read the medicine name AND the OCR text.
          await _speak(
            "Medication identified as $medTitle. "
                "The label says: $result",
          );
        } catch (e) {
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

              await _speak(
                "The image is too blurry. "
                    "Please hold the medication steady and try again.",
              );
            } else {
              onStatusUpdated(
                "The medication could not be scanned.",
              );

              await _speak(
                "The medication could not be scanned. "
                    "Please try again.",
              );
            }
          } else if (isBlurry) {
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


  Future<void> forceSaveLabel(
      String medTitle,
      ) async {
    final forcedScan = ScannedLabels(
      text: medTitle,
      times:
      DateTime.now().toIso8601String(),
    );

    await _dbService.insertLabels(
      forcedScan,
    );

    onStatusUpdated(
      "Medication saved.",
    );

    onMedicationScanned?.call(
      MedicationScanResult(
        medicationName: medTitle,
        labelText: _lastScannedText,
        saved: true,
        duplicate: false,
      ),
    );

    await _speak(
      "$medTitle has been saved. "
          "The label says: $_lastScannedText",
    );
  }
}