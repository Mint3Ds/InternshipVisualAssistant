import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';

import '../core/camera_scanning.dart';

class AccessibilitySettings {
  bool voiceGuidance = false;
  bool largeText = true;
  bool highContrast = false;
  bool hapticFeedback = true;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late ScannerController _scanner;

  final AccessibilitySettings _accessibility =
  AccessibilitySettings();

  String _statusMessage =
      "Point the camera at a medication label to scan.";

  bool _cameraInitialized = false;

  DebugFrameInfo? _debugFrame;

  MedicationScanResult? _scanResult;

  DateTime _lastHapticTime =
  DateTime.fromMillisecondsSinceEpoch(0);

  final ScrollController _pageScrollController =
  ScrollController();

  final ScrollController _resultScrollController =
  ScrollController();

  @override
  void initState() {
    super.initState();

    _scanner = ScannerController(
      onStatusUpdated: _handleStatusUpdated,
      onWarningTriggered: _handleWarning,
      onCameraInitialized: _handleCameraInitialized,
      onDebugFrame: _handleDebugFrame,
      onMedicationScanned: _handleMedicationScanned,
    );

    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      await _scanner.initializeCamera();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _statusMessage =
        "Camera could not be initialized.";
      });
    }
  }

  void _handleCameraInitialized() {
    if (!mounted) return;

    setState(() {
      _cameraInitialized = true;
    });
  }

  void _handleStatusUpdated(String message) {
    if (!mounted) return;

    setState(() {
      _statusMessage = message;
    });
  }

  void _handleDebugFrame(DebugFrameInfo? frame) {
    if (!mounted) return;

    setState(() {
      _debugFrame = frame;
    });

    if (frame != null &&
        frame.isWellPositioned &&
        _accessibility.hapticFeedback) {
      _handleHapticPositionFeedback();
    }
  }

  void _handleHapticPositionFeedback() {
    final now = DateTime.now();

    if (now.difference(_lastHapticTime) <
        const Duration(milliseconds: 500)) {
      return;
    }

    _lastHapticTime = now;

    HapticFeedback.mediumImpact();
  }

  void _handleMedicationScanned(
      MedicationScanResult result,
      ) {
    if (!mounted) return;

    setState(() {
      _scanResult = result;
    });

    // Give Flutter a moment to build the result card,
    // then scroll down to it.
    Future.delayed(
      const Duration(milliseconds: 150),
          () {
        if (!mounted ||
            !_pageScrollController.hasClients) {
          return;
        }

        _pageScrollController.animateTo(
          _pageScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      },
    );
  }

  void _handleWarning(String medTitle) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final bool highContrast =
            _accessibility.highContrast;

        return AlertDialog(
          backgroundColor:
          highContrast ? Colors.black : Colors.white,
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: highContrast
                    ? Colors.yellow
                    : Colors.orange,
                size: 30,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Recently Scanned",
                  style: TextStyle(
                    color: highContrast
                        ? Colors.white
                        : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            "'$medTitle' was scanned within the last 4 hours.\n\n"
                "Would you like to save it again?",
            style: TextStyle(
              color: highContrast
                  ? Colors.white
                  : Colors.black87,
              fontSize: 16,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);

                _scanner.resumeLiveScanning();

                setState(() {
                  _scanResult = null;
                });
              },
              child: Text(
                "Cancel",
                style: TextStyle(
                  color: highContrast
                      ? Colors.white
                      : Theme.of(context)
                      .colorScheme
                      .primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);

                await _scanner.forceSaveLabel(
                  medTitle,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: highContrast
                    ? Colors.white
                    : Theme.of(context)
                    .colorScheme
                    .primary,
                foregroundColor: highContrast
                    ? Colors.black
                    : Colors.white,
              ),
              child: const Text(
                "Log Anyway",
              ),
            ),
          ],
        );
      },
    );
  }

  void _scanAgain() {
    setState(() {
      _scanResult = null;
      _statusMessage =
      "Point the camera at a medication label to scan.";
      _debugFrame = null;
    });

    _scanner.resumeLiveScanning();

    Future.delayed(
      const Duration(milliseconds: 100),
          () {
        if (!mounted ||
            !_pageScrollController.hasClients) {
          return;
        }

        _pageScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      },
    );
  }

  @override
  void dispose() {
    _pageScrollController.dispose();
    _resultScrollController.dispose();
    _scanner.dispose();
    super.dispose();
  }

  double _textScale() {
    return _accessibility.largeText ? 1.15 : 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final bool highContrast =
        _accessibility.highContrast;

    final Color backgroundColor =
    highContrast ? Colors.black : Colors.white;

    final Color foregroundColor =
    highContrast ? Colors.white : Colors.black87;

    final Color secondaryColor =
    highContrast ? Colors.white : Colors.black54;

    final screenHeight =
        MediaQuery.of(context).size.height;

    final cameraHeight = screenHeight < 700
        ? 250.0
        : screenHeight < 850
        ? 320.0
        : 380.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: highContrast
            ? Colors.black
            : Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        title: Text(
          "Medication Scanner",
          style: TextStyle(
            fontSize: 20 * _textScale(),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: "Accessibility settings",
            onPressed: _openAccessibilitySettings,
            icon: const Icon(
              Icons.accessibility_new,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Scrollbar(
          controller: _pageScrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 7,
          radius: const Radius.circular(10),
          child: SingleChildScrollView(
            controller: _pageScrollController,
            padding: const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              32,
            ),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.stretch,
              children: [
                // STATUS
                _buildStatusCard(
                  foregroundColor,
                  secondaryColor,
                  highContrast,
                ),

                const SizedBox(height: 16),

                // CAMERA
                _buildCameraPreview(
                  cameraHeight,
                  highContrast,
                ),

                const SizedBox(height: 16),

                // SCAN BUTTON
                SizedBox(
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed: _cameraInitialized &&
                        _scanResult == null
                        ? () {
                      _scanner.captureNext();
                    }
                        : null,
                    icon: const Icon(
                      Icons.camera_alt,
                      size: 28,
                    ),
                    label: Text(
                      "Scan Medication",
                      style: TextStyle(
                        fontSize: 18 * _textScale(),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: highContrast
                          ? Colors.white
                          : Theme.of(context)
                          .colorScheme
                          .primary,
                      foregroundColor: highContrast
                          ? Colors.black
                          : Colors.white,
                      disabledBackgroundColor:
                      highContrast
                          ? Colors.grey.shade800
                          : Colors.grey.shade300,
                      disabledForegroundColor:
                      highContrast
                          ? Colors.grey.shade500
                          : Colors.grey.shade600,
                      shape:
                      RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(14),
                      ),
                      side: highContrast
                          ? const BorderSide(
                        color: Colors.white,
                        width: 2,
                      )
                          : null,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // SCAN RESULT
                if (_scanResult != null)
                  _buildMedicationResult(
                    _scanResult!,
                    highContrast,
                    foregroundColor,
                    secondaryColor,
                  ),

                const SizedBox(height: 16),

                // LIVE POSITION FEEDBACK
                if (_scanResult == null &&
                    _debugFrame != null)
                  _buildPositionFeedback(
                    _debugFrame!,
                    highContrast,
                    foregroundColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(
      Color foregroundColor,
      Color secondaryColor,
      bool highContrast,
      ) {
    return Semantics(
      liveRegion: true,
      label: "Scanner status",
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: highContrast
              ? Colors.black
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highContrast
                ? Colors.white
                : Colors.grey.shade300,
            width: highContrast ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: foregroundColor,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _statusMessage,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 16 * _textScale(),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview(
      double cameraHeight,
      bool highContrast,
      ) {
    return Container(
      height: cameraHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highContrast
              ? Colors.white
              : Colors.black,
          width: highContrast ? 3 : 1,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: !_cameraInitialized ||
          _scanner.cameraController == null
          ? const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      )
          : Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(
            _scanner.cameraController!,
          ),

          if (_debugFrame != null)
            CustomPaint(
              painter: OCRBoundingBoxPainter(
                debugFrame: _debugFrame!,
              ),
            ),

          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color:
                Colors.black.withOpacity(0.75),
                borderRadius:
                BorderRadius.circular(10),
              ),
              child: Text(
                "Position the medication label inside the frame",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize:
                  14 * _textScale(),
                  fontWeight:
                  FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionFeedback(
      DebugFrameInfo frame,
      bool highContrast,
      Color foregroundColor,
      ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highContrast
            ? Colors.black
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: frame.isWellPositioned
              ? (highContrast
              ? Colors.white
              : Colors.green)
              : (highContrast
              ? Colors.white
              : Colors.orange),
          width: highContrast ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            frame.isWellPositioned
                ? Icons.check_circle_outline
                : Icons.center_focus_strong,
            color: foregroundColor,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              frame.feedbackMessage,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 16 * _textScale(),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationResult(
      MedicationScanResult result,
      bool highContrast,
      Color foregroundColor,
      Color secondaryColor,
      ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: highContrast
            ? Colors.black
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highContrast
              ? Colors.white
              : Theme.of(context)
              .colorScheme
              .primary,
          width: highContrast ? 3 : 2,
        ),
        boxShadow: highContrast
            ? null
            : [
          BoxShadow(
            blurRadius: 8,
            offset: const Offset(0, 3),
            color: Colors.black
                .withOpacity(0.08),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                result.duplicate
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle,
                color: foregroundColor,
                size: 32,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.duplicate
                      ? "Medication Scanned"
                      : "Medication Identified",
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 21 * _textScale(),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            "Medication name",
            style: TextStyle(
              color: secondaryColor,
              fontSize: 14 * _textScale(),
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            result.medicationName,
            style: TextStyle(
              color: foregroundColor,
              fontSize: 24 * _textScale(),
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),

          Text(
            "Label information",
            style: TextStyle(
              color: foregroundColor,
              fontSize: 18 * _textScale(),
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Container(
            constraints: const BoxConstraints(
              maxHeight: 220,
            ),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: highContrast
                  ? Colors.black
                  : Colors.grey.shade100,
              borderRadius:
              BorderRadius.circular(12),
              border: Border.all(
                color: highContrast
                    ? Colors.white
                    : Colors.grey.shade400,
              ),
            ),
            child: Scrollbar(
              controller:
              _resultScrollController,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                controller:
                _resultScrollController,
                child: Text(
                  result.labelText.isEmpty
                      ? "No additional label information was detected."
                      : result.labelText,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 16 * _textScale(),
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          if (result.saved)
            Row(
              children: [
                Icon(
                  Icons.storage,
                  color: foregroundColor,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "This medication has been saved.",
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize:
                      15 * _textScale(),
                      fontWeight:
                      FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 18),

          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _scanAgain,
              icon: const Icon(
                Icons.refresh,
                size: 26,
              ),
              label: Text(
                "Scan Again",
                style: TextStyle(
                  fontSize: 17 * _textScale(),
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: highContrast
                    ? Colors.white
                    : Theme.of(context)
                    .colorScheme
                    .primary,
                foregroundColor: highContrast
                    ? Colors.black
                    : Colors.white,
                side: highContrast
                    ? const BorderSide(
                  color: Colors.white,
                  width: 2,
                )
                    : null,
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessibleSwitch({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final bool highContrast =
        _accessibility.highContrast;

    final Color foreground =
    highContrast ? Colors.white : Colors.black87;

    final Color secondary =
    highContrast ? Colors.white : Colors.black54;

    final Color border =
    highContrast
        ? Colors.white
        : Colors.grey.shade400;

    return Semantics(
      label: title,
      hint: description,
      toggled: value,
      child: InkWell(
        onTap: () {
          onChanged(!value);
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: highContrast
                ? Colors.black
                : Colors.grey.shade50,
            borderRadius:
            BorderRadius.circular(14),
            border: Border.all(
              color: border,
              width: highContrast ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: foreground,
                size: 28,
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 17,
                        fontWeight:
                        FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: secondary,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Switch(
                value: value,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAccessibilitySettings() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (
              context,
              setSheetState,
              ) {
            final bool highContrast =
                _accessibility.highContrast;

            final Color background =
            highContrast
                ? Colors.black
                : Colors.white;

            final Color foreground =
            highContrast
                ? Colors.white
                : Colors.black87;

            final Color secondary =
            highContrast
                ? Colors.white
                : Colors.black54;

            final Color border =
            highContrast
                ? Colors.white
                : Colors.grey.shade400;

            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight:
                  MediaQuery.of(context)
                      .size
                      .height *
                      0.90,
                ),
                decoration: BoxDecoration(
                  color: background,
                  border: Border(
                    top: BorderSide(
                      color: border,
                      width:
                      highContrast ? 3 : 1,
                    ),
                  ),
                  borderRadius:
                  const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  trackVisibility: true,
                  thickness: 7,
                  radius:
                  const Radius.circular(10),
                  child: SingleChildScrollView(
                    padding:
                    const EdgeInsets.fromLTRB(
                      20,
                      16,
                      20,
                      32,
                    ),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 45,
                            height: 5,
                            decoration:
                            BoxDecoration(
                              color: secondary,
                              borderRadius:
                              BorderRadius
                                  .circular(10),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        Row(
                          children: [
                            Icon(
                              Icons
                                  .accessibility_new,
                              color: foreground,
                              size: 30,
                            ),
                            const SizedBox(
                              width: 12,
                            ),
                            Expanded(
                              child: Text(
                                "Accessibility Settings",
                                style: TextStyle(
                                  color:
                                  foreground,
                                  fontSize: 23,
                                  fontWeight:
                                  FontWeight
                                      .bold,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        Text(
                          "Adjust the scanner to make it easier to use.",
                          style: TextStyle(
                            color: secondary,
                            fontSize: 16,
                            height: 1.4,
                          ),
                        ),

                        const SizedBox(height: 20),

                        // VOICE GUIDANCE
                        _buildAccessibleSwitch(
                          context: context,
                          title: "Voice guidance",
                          description:
                          "Reads scanning instructions and medication results aloud.",
                          icon:
                          Icons.volume_up_outlined,
                          value: _accessibility
                              .voiceGuidance,
                          onChanged: (value) async {
                            // Update HomePage's setting.
                            _accessibility
                                .voiceGuidance = value;

                            // IMPORTANT:
                            // Rebuild the bottom sheet immediately.
                            setSheetState(() {});

                            // Update the scanner.
                            await _scanner
                                .setVoiceGuidance(
                              value,
                            );
                          },
                        ),

                        const SizedBox(height: 12),

                        // LARGE TEXT
                        _buildAccessibleSwitch(
                          context: context,
                          title: "Large text",
                          description:
                          "Increases the size of text throughout the app.",
                          icon: Icons.text_fields,
                          value:
                          _accessibility.largeText,
                          onChanged: (value) {
                            _accessibility
                                .largeText = value;

                            setSheetState(() {});
                          },
                        ),

                        const SizedBox(height: 12),

                        // HIGH CONTRAST
                        _buildAccessibleSwitch(
                          context: context,
                          title: "High contrast",
                          description:
                          "Uses stronger contrast between text, controls and backgrounds.",
                          icon: Icons.contrast,
                          value: _accessibility
                              .highContrast,
                          onChanged: (value) {
                            _accessibility
                                .highContrast = value;

                            setSheetState(() {});
                          },
                        ),

                        const SizedBox(height: 12),

                        // HAPTIC FEEDBACK
                        _buildAccessibleSwitch(
                          context: context,
                          title: "Haptic feedback",
                          description:
                          "Provides vibration feedback when the medication is positioned correctly.",
                          icon: Icons.vibration,
                          value: _accessibility
                              .hapticFeedback,
                          onChanged: (value) {
                            _accessibility
                                .hapticFeedback = value;

                            setSheetState(() {});

                            if (value) {
                              HapticFeedback
                                  .mediumImpact();
                            }
                          },
                        ),

                        const SizedBox(height: 24),

                        // SCREEN READER INFO
                        Container(
                          padding:
                          const EdgeInsets.all(
                            16,
                          ),
                          decoration:
                          BoxDecoration(
                            color: highContrast
                                ? Colors.black
                                : Colors.grey.shade100,
                            border: Border.all(
                              color: border,
                              width: highContrast
                                  ? 2
                                  : 1,
                            ),
                            borderRadius:
                            BorderRadius
                                .circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons
                                        .record_voice_over,
                                    color:
                                    foreground,
                                  ),
                                  const SizedBox(
                                    width: 10,
                                  ),
                                  Expanded(
                                    child: Text(
                                      "Screen readers",
                                      style:
                                      TextStyle(
                                        color:
                                        foreground,
                                        fontSize: 18,
                                        fontWeight:
                                        FontWeight
                                            .bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(
                                height: 8,
                              ),

                              Text(
                                "The app supports Android TalkBack and iOS VoiceOver. Buttons and settings have descriptive labels.",
                                style: TextStyle(
                                  color: secondary,
                                  fontSize: 15,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        SizedBox(
                          height: 56,
                          child:
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(
                                context,
                              );
                            },
                            style: ElevatedButton
                                .styleFrom(
                              backgroundColor:
                              highContrast
                                  ? Colors.white
                                  : Theme.of(
                                context,
                              )
                                  .colorScheme
                                  .primary,
                              foregroundColor:
                              highContrast
                                  ? Colors.black
                                  : Colors.white,
                              side: highContrast
                                  ? const BorderSide(
                                color:
                                Colors
                                    .white,
                                width: 2,
                              )
                                  : null,
                              shape:
                              RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius
                                    .circular(
                                  14,
                                ),
                              ),
                            ),
                            child: const Text(
                              "Done",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight:
                                FontWeight
                                    .bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    // Rebuild HomePage after the settings sheet closes.
    if (mounted) {
      setState(() {});
    }
  }
}

class OCRBoundingBoxPainter extends CustomPainter {
  final DebugFrameInfo debugFrame;

  OCRBoundingBoxPainter({
    required this.debugFrame,
  });

  @override
  void paint(
      Canvas canvas,
      Size size,
      ) {
    if (debugFrame.blockBoxes.isEmpty) {
      return;
    }

    final double scaleX =
        size.width / debugFrame.effectiveWidth;

    final double scaleY =
        size.height / debugFrame.effectiveHeight;

    final Paint blockPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.yellow;

    final Paint unionPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = debugFrame.isWellPositioned
          ? Colors.green
          : Colors.red;

    for (final Rect box
    in debugFrame.blockBoxes) {
      final Rect scaled = Rect.fromLTRB(
        box.left * scaleX,
        box.top * scaleY,
        box.right * scaleX,
        box.bottom * scaleY,
      );

      canvas.drawRect(
        scaled,
        blockPaint,
      );
    }

    if (debugFrame.unionBox != null) {
      final Rect box = debugFrame.unionBox!;

      final Rect scaled = Rect.fromLTRB(
        box.left * scaleX,
        box.top * scaleY,
        box.right * scaleX,
        box.bottom * scaleY,
      );

      canvas.drawRect(
        scaled,
        unionPaint,
      );
    }
  }

  @override
  bool shouldRepaint(
      covariant OCRBoundingBoxPainter oldDelegate,
      ) {
    return oldDelegate.debugFrame != debugFrame;
  }
}