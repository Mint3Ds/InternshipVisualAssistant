import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../core/database.dart';
import '../core/image_processor_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ============================================================
  // CAMERA
  // ============================================================

  List<CameraDescription> cameras = [];
  CameraController? cameraController;

  bool _captureNextFrame = false;
  bool _isScanning = false;
  bool _cameraReady = false;
  bool _cameraError = false;

  // ============================================================
  // SERVICES
  // ============================================================

  final OCRProcess _ocrService = OCRProcess();
  final DatabaseService _dbService = DatabaseService();
  final TitleExtraction _titleExtract = TitleExtraction();

  final FlutterTts _tts = FlutterTts();

  // ============================================================
  // UI STATE
  // ============================================================

  String _scanResult = "Ready to scan";

  String _statusMessage =
      "Point the camera at the medicine label, then press Scan Medicine.";

  String _instructionMessage =
      "Point the camera at the medicine label.";

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();

    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Set up TTS first.
    await _setupTts();

    // Then start the camera.
    await _setupCameraController();
  }

  @override
  void dispose() {
    cameraController?.dispose();
    _tts.stop();
    super.dispose();
  }

  // ============================================================
  // TEXT TO SPEECH
  // ============================================================

  Future<void> _setupTts() async {
    try {
      await _tts.setLanguage("en-US");

      await _tts.setSpeechRate(0.45);

      await _tts.setVolume(1.0);

      await _tts.setPitch(1.0);

      // Give the TTS engine a moment to initialise.
      await Future.delayed(
        const Duration(milliseconds: 1000),
      );

      if (!mounted) return;

      await _speak(
        "Medicine scanner ready. "
        "Point the camera at the medicine label. "
        "When the label is in view, press the Scan Medicine button.",
      );
    } catch (e) {
      debugPrint("TTS setup error: $e");
    }
  }

  Future<void> _speak(String message) async {
    try {
      debugPrint("TTS speaking: $message");

      await _tts.stop();

      await _tts.speak(message);
    } catch (e) {
      debugPrint("TTS error: $e");
    }
  }

  // ============================================================
  // MAIN UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildUI(),
    );
  }

  // ============================================================
  // UI
  // ============================================================

  Widget _buildUI() {
    // ----------------------------------------------------------
    // CAMERA LOADING
    // ----------------------------------------------------------

    if (!_cameraReady) {
      return _buildCameraLoadingScreen();
    }

    // ----------------------------------------------------------
    // CAMERA READY
    // ----------------------------------------------------------

    return SafeArea(
      child: Column(
        children: [
          // ======================================================
          // HEADER
          // ======================================================

          Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              18,
              20,
              8,
            ),
            child: Semantics(
              header: true,
              label: "Medicine Scanner",
              child: const Text(
                "MEDICINE SCANNER",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),

          // ======================================================
          // STATUS
          // ======================================================

          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              child: Semantics(
                liveRegion: true,
                container: true,
                label: _statusMessage,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          // Decorative icon.
                          ExcludeSemantics(
                            child: Icon(
                              _isScanning
                                  ? Icons.hourglass_top
                                  : Icons.accessibility_new,
                              color: Colors.white,
                              size: 42,
                            ),
                          ),

                          const SizedBox(height: 12),

                          Text(
                            _statusMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                              height: 1.4,
                            ),
                          ),

                          // ------------------------------------------------
                          // RESULT
                          // ------------------------------------------------

                          if (!_isScanning &&
                              _scanResult != "Ready to scan") ...[
                            const SizedBox(height: 16),

                            const Divider(
                              color: Colors.white,
                              thickness: 1,
                            ),

                            const SizedBox(height: 12),

                            const Text(
                              "SCAN RESULT",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),

                            const SizedBox(height: 8),

                            Semantics(
                              label:
                                  "Detected text: $_scanResult",
                              child: Text(
                                _scanResult,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ======================================================
          // CAMERA
          // ======================================================

          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Semantics(
                container: true,
                label:
                    "Camera preview. "
                    "Point the camera towards the front of the medicine package. "
                    "The camera preview is visual only.",
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white,
                        width: 4,
                      ),
                      borderRadius:
                          BorderRadius.circular(20),
                    ),
                    child: FittedBox(
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: cameraController!
                                .value
                                .previewSize
                                ?.height ??
                            1,
                        height: cameraController!
                                .value
                                .previewSize
                                ?.width ??
                            1,
                        child: CameraPreview(
                          cameraController!,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ======================================================
          // INSTRUCTION
          // ======================================================

          Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              10,
              20,
              8,
            ),
            child: Semantics(
              liveRegion: true,
              label: _instructionMessage,
              child: Text(
                _instructionMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                ),
              ),
            ),
          ),

          // ======================================================
          // SCAN BUTTON
          // ======================================================

          Padding(
            padding: const EdgeInsets.fromLTRB(
              24,
              8,
              24,
              10,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 86,
              child: Semantics(
                button: true,
                enabled: !_isScanning,
                label: _isScanning
                    ? "Scanning medicine"
                    : "Scan medicine",
                hint: _isScanning
                    ? "Scanning is in progress. Please wait."
                    : "Double tap to scan the medicine label.",
                child: ElevatedButton.icon(
                  onPressed:
                      _isScanning ? null : _startScan,
                  icon: ExcludeSemantics(
                    child: Icon(
                      _isScanning
                          ? Icons.hourglass_top
                          : Icons.camera_alt,
                      size: 36,
                    ),
                  ),
                  label: Text(
                    _isScanning
                        ? "SCANNING..."
                        : "SCAN MEDICINE",
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor:
                        Colors.grey.shade700,
                    disabledForegroundColor:
                        Colors.white,
                    elevation: 6,
                    minimumSize:
                        const Size(double.infinity, 86),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ======================================================
          // TEST AUDIO BUTTON
          // ======================================================
          //
          // TEMPORARY:
          // Use this to check whether flutter_tts itself
          // works on the emulator / phone.
          //
          // Remove this button when testing is complete.
          // ======================================================

          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 4,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: Semantics(
                button: true,
                label: "Test audio",
                hint:
                    "Double tap to test text to speech.",
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _speak(
                      "Hello. "
                      "This is a text to speech test. "
                      "The medicine scanner audio is working.",
                    );
                  },
                  icon: const Icon(
                    Icons.volume_up,
                    size: 28,
                  ),
                  label: const Text(
                    "TEST AUDIO",
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(
                      color: Colors.white,
                      width: 2,
                    ),
                    minimumSize:
                        const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ======================================================
          // SCAN ANOTHER
          // ======================================================

          if (!_isScanning &&
              _scanResult != "Ready to scan")
            Padding(
              padding: const EdgeInsets.only(
                top: 4,
                bottom: 12,
              ),
              child: Semantics(
                button: true,
                label: "Scan another medicine",
                hint:
                    "Double tap to start another scan.",
                child: TextButton(
                  onPressed: _resetForNewScan,
                  style: TextButton.styleFrom(
                    minimumSize:
                        const Size(220, 48),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    "SCAN ANOTHER MEDICINE",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      decoration:
                          TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ============================================================
  // CAMERA LOADING SCREEN
  // ============================================================

  Widget _buildCameraLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Semantics(
            liveRegion: true,
            label: _cameraError
                ? "Unable to start the camera."
                : "Starting medicine scanner camera.",
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  if (!_cameraError)
                    const SizedBox(
                      width: 65,
                      height: 65,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 5,
                      ),
                    )
                  else
                    const ExcludeSemantics(
                      child: Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 65,
                      ),
                    ),

                  const SizedBox(height: 30),

                  Text(
                    _cameraError
                        ? "Unable to start camera"
                        : "Starting camera...",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  if (_cameraError) ...[
                    const SizedBox(height: 16),

                    const Text(
                      "Please check camera permissions "
                      "and try again.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(height: 24),

                    Semantics(
                      button: true,
                      label: "Retry camera",
                      hint:
                          "Double tap to try starting the camera again.",
                      child: ElevatedButton(
                        onPressed:
                            _setupCameraController,
                        style:
                            ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          minimumSize:
                              const Size(220, 60),
                        ),
                        child: const Text(
                          "RETRY",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // START SCAN
  // ============================================================

  Future<void> _startScan() async {
    if (_isScanning) {
      return;
    }

    if (cameraController == null ||
        !cameraController!.value.isInitialized) {
      await _speak(
        "The camera is not ready. "
        "Please wait and try again.",
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _captureNextFrame = true;

      _scanResult = "Scanning...";

      _statusMessage =
          "Scanning the medicine label. Please hold still.";

      _instructionMessage =
          "Hold the camera steady.";
    });

    // ----------------------------------------------------------
    // HAPTIC START FEEDBACK
    // ----------------------------------------------------------

    await HapticFeedback.mediumImpact();

    // ----------------------------------------------------------
    // AUDIO START FEEDBACK
    // ----------------------------------------------------------

    await _speak(
      "Scanning the medicine label. "
      "Please hold the camera still.",
    );
  }

  // ============================================================
  // RESET FOR NEW SCAN
  // ============================================================

  Future<void> _resetForNewScan() async {
    if (_isScanning) {
      return;
    }

    setState(() {
      _scanResult = "Ready to scan";

      _statusMessage =
          "Point the camera at the medicine label, "
          "then press Scan Medicine.";

      _instructionMessage =
          "Point the camera at the medicine label.";
    });

    await HapticFeedback.selectionClick();

    await _speak(
      "Ready to scan. "
      "Point the camera at the medicine label, "
      "then press Scan Medicine.",
    );
  }

  // ============================================================
  // CAMERA SETUP
  // ============================================================

  Future<void> _setupCameraController() async {
    try {
      final List<CameraDescription> available =
          await availableCameras();

      if (available.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraError = true;
            _cameraReady = false;

            _statusMessage =
                "No camera was found on this device.";
          });
        }

        await _speak(
          "No camera was found on this device.",
        );

        return;
      }

      // --------------------------------------------------------
      // DISPOSE OLD CONTROLLER IF RETRYING
      // --------------------------------------------------------

      await cameraController?.dispose();

      // --------------------------------------------------------
      // CREATE CAMERA CONTROLLER
      // --------------------------------------------------------

      final CameraController controller =
          CameraController(
        available.first,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      cameraController = controller;

      cameras = available;

      // --------------------------------------------------------
      // INITIALISE CAMERA
      // --------------------------------------------------------

      await controller.initialize();

      if (!mounted) {
        return;
      }

      // --------------------------------------------------------
      // AUTO FOCUS
      // --------------------------------------------------------

      try {
        await controller.setFocusMode(
          FocusMode.auto,
        );
      } catch (e) {
        debugPrint(
          "Could not set autofocus: $e",
        );
      }

      // --------------------------------------------------------
      // CAMERA READY
      // --------------------------------------------------------

      setState(() {
        _cameraReady = true;
        _cameraError = false;
      });

      // --------------------------------------------------------
      // IMAGE STREAM
      // --------------------------------------------------------

      await controller.startImageStream(
        (CameraImage image) async {
          // ------------------------------------------------------
          // WAIT FOR USER TO PRESS SCAN
          // ------------------------------------------------------

          if (!_captureNextFrame) {
            return;
          }

          // ------------------------------------------------------
          // PREVENT MULTIPLE FRAMES
          // ------------------------------------------------------

          _captureNextFrame = false;

          try {
            // ==================================================
            // CONVERT CAMERA IMAGE TO BYTES
            // ==================================================

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
                controller
                    .description
                    .sensorOrientation;

            // ==================================================
            // OCR
            // ==================================================

            final RecognizedText result =
                await _ocrService.scanLabel(
              rawBytes,
              image.width,
              image.height,
              isAndroid,
              sensorOrientation,
            );

            final String detectedText =
                result.text.trim();

            // ==================================================
            // MEDICINE TITLE EXTRACTION
            // ==================================================

            final String medicineTitle =
                _titleExtract
                    .extractTitle(result)
                    .trim();

            // ==================================================
            // DATABASE
            // ==================================================

            if (medicineTitle.isNotEmpty) {
              final newScan = ScannedLabels(
                text: medicineTitle,
                times: DateTime.now()
                    .toIso8601String(),
              );

              await _dbService.insertLabels(
                newScan,
              );

              debugPrint(
                "Successfully saved to database!",
              );

              // ------------------------------------------------
              // DEBUG DATABASE OUTPUT
              // ------------------------------------------------

              final savedLabels =
                  await _dbService.outPutLabels(
                limitCount: 3,
              );

              debugPrint(
                "--- CURRENT DATABASE LOGS ---",
              );

              for (final label in savedLabels) {
                debugPrint(
                  "ID: ${label.id} | "
                  "Text: ${label.text} | "
                  "Time: ${label.times}",
                );
              }

              debugPrint(
                "-----------------------------",
              );
            }

            // ==================================================
            // SUCCESS UI
            // ==================================================

            if (!mounted) {
              return;
            }

            final String displayResult =
                detectedText.isEmpty
                    ? "No text found."
                    : detectedText;

            setState(() {
              _isScanning = false;

              _scanResult = displayResult;

              if (detectedText.isEmpty) {
                _statusMessage =
                    "No medicine text was detected.";

                _instructionMessage =
                    "Move the camera closer, "
                    "make sure the label is visible, "
                    "and try again.";
              } else if (medicineTitle.isNotEmpty) {
                _statusMessage =
                    "Medicine detected.";

                _instructionMessage =
                    "The medicine name was detected. "
                    "You can scan another medicine.";
              } else {
                _statusMessage =
                    "Text detected.";

                _instructionMessage =
                    "Text was detected, but the medicine "
                    "name could not be identified.";
              }
            });

            // ==================================================
            // SUCCESS HAPTIC
            // ==================================================

            await HapticFeedback.heavyImpact();

            // ==================================================
            // ACCESSIBLE VOICE RESULT
            // ==================================================

            if (medicineTitle.isNotEmpty) {
              await _speak(
                "Medicine detected. "
                "The medicine appears to be "
                "$medicineTitle.",
              );
            } else if (detectedText.isNotEmpty) {
              String speechText =
                  detectedText.replaceAll(
                RegExp(r'\s+'),
                ' ',
              );

              // Limit spoken OCR result.
              if (speechText.length > 250) {
                speechText =
                    speechText.substring(0, 250);
              }

              await _speak(
                "Text detected. "
                "$speechText",
              );
            } else {
              await _speak(
                "No medicine text was detected. "
                "Move the camera closer, "
                "make sure the label is visible, "
                "and try again.",
              );
            }
          } catch (e) {
            // ==================================================
            // ERROR HANDLING
            // ==================================================

            debugPrint(
              "Scan error: $e",
            );

            if (!mounted) {
              return;
            }

            final String error =
                e.toString();

            if (error.contains(
              "BLURRY_FRAME",
            )) {
              setState(() {
                _isScanning = false;

                _scanResult =
                    "Image too blurry.";

                _statusMessage =
                    "The image is too blurry.";

                _instructionMessage =
                    "Move closer to the medicine, "
                    "hold the camera still, "
                    "and try again.";
              });

              await HapticFeedback.vibrate();

              await _speak(
                "The image is too blurry. "
                "Move closer to the medicine, "
                "hold the camera still, "
                "and try again.",
              );
            } else {
              setState(() {
                _isScanning = false;

                _scanResult =
                    "Scan failed.";

                _statusMessage =
                    "The medicine could not be scanned.";

                _instructionMessage =
                    "Please reposition the camera "
                    "and try again.";
              });

              await HapticFeedback.vibrate();

              await _speak(
                "The medicine could not be scanned. "
                "Please reposition the camera "
                "and try again.",
              );
            }
          }
        },
      );
    } catch (e) {
      // ========================================================
      // CAMERA INITIALIZATION ERROR
      // ========================================================

      debugPrint(
        "Camera initialization error: $e",
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _cameraReady = false;
        _cameraError = true;
        _isScanning = false;
        _captureNextFrame = false;

        _statusMessage =
            "Unable to start the camera.";
      });

      await HapticFeedback.vibrate();

      await _speak(
        "Unable to start the camera. "
        "Please check the camera permission "
        "and try again.",
      );
    }
  }
}