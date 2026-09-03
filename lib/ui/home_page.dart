import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../core/camera_scanning.dart';

class AccessibilitySettings {
  bool voiceGuidance;
  bool largeText;
  bool highContrast;
  bool hapticFeedback;

  AccessibilitySettings({
    this.voiceGuidance = false,
    this.largeText = true,
    this.highContrast = false,
    this.hapticFeedback = true,
  });
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

  @override
  void initState() {
    super.initState();

    _scanner = ScannerController(
      onStatusUpdated: (message) {
        if (!mounted) return;

        setState(() {
          _statusMessage = message;
        });
      },
      onWarningTriggered: (medTitle) {
        if (!mounted) return;
        _showDuplicateWarning(medTitle);
      },
      onCameraInitialized: () {
        if (!mounted) return;

        setState(() {
          _cameraInitialized = true;
        });
      },
      onDebugFrame: (frame) {
        if (!mounted) return;

        setState(() {
          _debugFrame = frame;
        });
        if (frame != null) {
          _handleHapticPositionFeedback(frame);
        }
      },
    );

    _scanner.initializeCamera();
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  // haptic feedback
  // - medium vibration when positioned correctly
  // - light vibration when not positioned correctly
  //
  // The accessibility switch controls whether these vibrations happen.
  void _handleHapticPositionFeedback(DebugFrameInfo frame) {
    if (!_accessibility.hapticFeedback) return;

    if (frame.isWellPositioned) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  void _buttonHaptic() {
    if (_accessibility.hapticFeedback) {
      HapticFeedback.mediumImpact();
    }
  }

  // Accessibility theme
  ThemeData _buildAccessibleTheme(BuildContext context) {
    final textScale =
    _accessibility.largeText ? 1.25 : 1.0;

    if (_accessibility.highContrast) {
      return Theme.of(context).copyWith(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,

        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          onPrimary: Colors.black,
          secondary: Colors.yellow,
          onSecondary: Colors.black,
          surface: Colors.black,
          onSurface: Colors.white,
          error: Colors.yellow,
          onError: Colors.black,
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),

        cardTheme: const CardThemeData(
          color: Colors.black,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: Colors.white,
              width: 2,
            ),
            borderRadius: BorderRadius.all(
              Radius.circular(16),
            ),
          ),
        ),

        switchTheme: SwitchThemeData(
          thumbColor:
          WidgetStateProperty.resolveWith<Color>(
                (states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.black;
              }

              return Colors.white;
            },
          ),
          trackColor:
          WidgetStateProperty.resolveWith<Color>(
                (states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.yellow;
              }

              return Colors.black;
            },
          ),
          trackOutlineColor:
          WidgetStateProperty.all(Colors.white),
        ),

        textTheme: Theme.of(context)
            .textTheme
            .apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),

        elevatedButtonTheme:
        ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            minimumSize:
            const Size(double.infinity, 76),
            side: const BorderSide(
              color: Colors.white,
              width: 3,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: TextStyle(
              fontSize: 20 * textScale,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
          ),
        ),

        dividerTheme: const DividerThemeData(
          color: Colors.white,
          thickness: 2,
        ),
      );
    }

    return Theme.of(context).copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor:
      const Color(0xFFF5F5F5),

      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: Brightness.light,
      ),

      elevatedButtonTheme:
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize:
          const Size(double.infinity, 76),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: TextStyle(
            fontSize: 20 * textScale,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // Build
  @override
  Widget build(BuildContext context) {
    final textScale =
    _accessibility.largeText ? 1.25 : 1.0;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler:
        TextScaler.linear(textScale),
      ),
      child: Theme(
        data: _buildAccessibleTheme(context),
        child: Scaffold(
          backgroundColor:
          _accessibility.highContrast
              ? Colors.black
              : const Color(0xFFF5F5F5),
          appBar: _buildAppBar(),
          body: _buildUI(),
        ),
      ),
    );
  }

  // app bar
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Semantics(
        header: true,
        child: const Text(
          "Medication Scanner",
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      actions: [
        Semantics(
          button: true,
          label: "Accessibility settings",
          hint: "Open accessibility settings",
          child: IconButton(
            icon: const Icon(
              Icons.accessibility_new,
              size: 30,
            ),
            tooltip: "Accessibility settings",
            onPressed: () {
              _buttonHaptic();
              _showAccessibilitySettings();
            },
          ),
        ),
      ],
    );
  }

  // main ui
  Widget _buildUI() {
    final highContrast =
        _accessibility.highContrast;

    final pageBackground =
    highContrast
        ? Colors.black
        : const Color(0xFFF5F5F5);

    final primaryText =
    highContrast
        ? Colors.white
        : Colors.black;

    final statusBackground =
    highContrast
        ? Colors.black
        : Colors.white;

    final borderColor =
    highContrast
        ? Colors.white
        : Colors.black;

    return Container(
      color: pageBackground,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [

              // status card

              Semantics(
                liveRegion: true,
                label: "Scanner status",
                value: _statusMessage,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin:
                  const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: statusBackground,
                    borderRadius:
                    BorderRadius.circular(16),
                    border: Border.all(
                      color: borderColor,
                      width: highContrast ? 3 : 1,
                    ),
                  ),
                  child: Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ),

              // Camera
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius:
                    BorderRadius.circular(16),
                    border: Border.all(
                      color: highContrast
                          ? Colors.white
                          : Colors.black,
                      width: highContrast ? 4 : 2,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _cameraInitialized &&
                      _scanner.cameraController !=
                          null &&
                      _scanner.cameraController!
                          .value
                          .isInitialized
                      ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(
                        _scanner.cameraController!,
                      ),

                      // OCR bounding boxes
                      if (_debugFrame != null)
                        CustomPaint(
                          painter:
                          _BoundingBoxPainter(
                            frame: _debugFrame!,
                            highContrast:
                            highContrast,
                          ),
                        ),

                      // Positioning feedback
                      if (_debugFrame != null &&
                          _debugFrame!
                              .feedbackMessage
                              .isNotEmpty)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Semantics(
                            liveRegion: true,
                            label:
                            "Positioning feedback",
                            value: _debugFrame!
                                .feedbackMessage,
                            child: Container(
                              padding:
                              const EdgeInsets.all(
                                  12),
                              decoration:
                              BoxDecoration(
                                color: Colors.black
                                    .withValues(
                                  alpha: 0.8,
                                ),
                                borderRadius:
                                BorderRadius
                                    .circular(12),
                                border: highContrast
                                    ? Border.all(
                                  color:
                                  Colors.white,
                                  width: 2,
                                )
                                    : null,
                              ),
                              child: Text(
                                _debugFrame!
                                    .feedbackMessage,
                                textAlign:
                                TextAlign.center,
                                style:
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight:
                                  FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                      : Semantics(
                    label:
                    "Camera preview loading",
                    child: const Center(
                      child:
                      CircularProgressIndicator(),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Scan button
              Semantics(
                button: true,
                label: _scanner.isLiveScanningActive
                    ? "Scan medication"
                    : "Scan another medication",
                hint:
                "Double tap to scan the medication label",
                enabled: true,
                child: ElevatedButton.icon(
                  icon: Icon(
                    _scanner.isLiveScanningActive
                        ? Icons.camera_alt
                        : Icons.refresh,
                    size: 28,
                  ),
                  label: Text(
                    _scanner.isLiveScanningActive
                        ? "Scan"
                        : "Scan Again",
                  ),
                  onPressed: () {
                    _buttonHaptic();

                    if (!_scanner
                        .isLiveScanningActive) {
                      _scanner
                          .resumeLiveScanning();
                    }

                    _scanner.captureNext();
                  },
                ),
              ),

              const SizedBox(height: 12),

              // bottom status

              Semantics(
                liveRegion: true,
                label: "Scanner instruction",
                child: Text(
                  _scanner.isLiveScanningActive
                      ? "Ready to scan"
                      : "Scan completed",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // accessibility settings
  void _showAccessibilitySettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
      _accessibility.highContrast
          ? Colors.black
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (
              context,
              setModalState,
              ) {
            final highContrast =
                _accessibility.highContrast;

            return Theme(
              data: _buildAccessibleTheme(context),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    24,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        // Drag handle
                        Center(
                          child: Container(
                            width: 45,
                            height: 5,
                            decoration: BoxDecoration(
                              color: highContrast
                                  ? Colors.white
                                  : Colors.grey,
                              borderRadius:
                              BorderRadius.circular(10),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        Text(
                          "Accessibility Settings",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight:
                            FontWeight.bold,
                            color: highContrast
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),

                        const SizedBox(height: 6),

                        Text(
                          "Adjust the scanner to make it easier to use.",
                          style: TextStyle(
                            fontSize: 15,
                            color: highContrast
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Voice guidance
                        _buildAccessibilitySwitch(
                          context: context,
                          setModalState:
                          setModalState,
                          title: "Voice Guidance",
                          description:
                          "Speak important scanning instructions and results.",
                          icon:
                          Icons.record_voice_over,
                          value: _accessibility
                              .voiceGuidance,
                          onChanged:
                              (value) async {
                            setModalState(() {
                              _accessibility
                                  .voiceGuidance = value;
                            });

                            setState(() {});

                            await _scanner
                                .setVoiceGuidance(
                              value,
                            );
                          },
                        ),

                        // large text

                        _buildAccessibilitySwitch(
                          context: context,
                          setModalState:
                          setModalState,
                          title: "Large Text",
                          description:
                          "Increase text size throughout the scanner.",
                          icon: Icons.text_fields,
                          value: _accessibility
                              .largeText,
                          onChanged: (value) {
                            setModalState(() {
                              _accessibility
                                  .largeText = value;
                            });

                            setState(() {});
                          },
                        ),

                        // High contrast

                        _buildAccessibilitySwitch(
                          context: context,
                          setModalState:
                          setModalState,
                          title: "High Contrast",
                          description:
                          "Use stronger borders, black backgrounds and bright text.",
                          icon:
                          Icons.contrast,
                          value: _accessibility
                              .highContrast,
                          onChanged: (value) {
                            setModalState(() {
                              _accessibility
                                  .highContrast = value;
                            });

                            setState(() {});
                          },
                        ),

                        // haptic feedback
                        _buildAccessibilitySwitch(
                          context: context,
                          setModalState:
                          setModalState,
                          title: "Haptic Feedback",
                          description:
                          "Use vibration to indicate important scanner states.",
                          icon:
                          Icons.vibration,
                          value: _accessibility
                              .hapticFeedback,
                          onChanged: (value) {
                            setModalState(() {
                              _accessibility
                                  .hapticFeedback = value;
                            });

                            setState(() {});
                          },
                        ),

                        const SizedBox(height: 12),

                        // =================================================================
                        // SCREEN READER INFORMATION
                        // =================================================================

                        Container(
                          width: double.infinity,
                          padding:
                          const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: highContrast
                                ? Colors.black
                                : const Color(
                              0xFFF5F5F5,
                            ),
                            borderRadius:
                            BorderRadius.circular(16),
                            border: Border.all(
                              color: highContrast
                                  ? Colors.white
                                  : Colors.black26,
                              width:
                              highContrast ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons
                                    .accessibility_new,
                                color: highContrast
                                    ? Colors.white
                                    : Colors.indigo,
                                size: 28,
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Screen Reader Support",
                                      style: TextStyle(
                                        fontWeight:
                                        FontWeight.bold,
                                        fontSize: 17,
                                        color:
                                        highContrast
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),

                                    const SizedBox(
                                      height: 6,
                                    ),

                                    Text(
                                      "This app supports VoiceOver on iOS and TalkBack on Android.",
                                      style: TextStyle(
                                        fontSize: 14,
                                        color:
                                        highContrast
                                            ? Colors.white
                                            : Colors.black87,
                                        height: 1.4,
                                      ),
                                    ),

                                    const SizedBox(
                                      height: 8,
                                    ),

                                    Text(
                                      "If you use VoiceOver or TalkBack, consider keeping Voice Guidance off to avoid overlapping speech.",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight:
                                        FontWeight.w600,
                                        color:
                                        highContrast
                                            ? Colors.yellow
                                            : Colors.black87,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
  }

  // accessibility switch

  Widget _buildAccessibilitySwitch({
    required BuildContext context,
    required StateSetter setModalState,
    required String title,
    required String description,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final highContrast =
        _accessibility.highContrast;

    return Semantics(
      toggled: value,
      label:
      "$title. ${value ? "On" : "Off"}. $description",
      child: Container(
        margin:
        const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: highContrast
              ? Colors.black
              : Colors.white,
          borderRadius:
          BorderRadius.circular(16),
          border: Border.all(
            color: highContrast
                ? Colors.white
                : Colors.black26,
            width: highContrast ? 2 : 1,
          ),
        ),
        child: SwitchListTile(
          contentPadding:
          const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          secondary: Icon(
            icon,
            size: 28,
            color: highContrast
                ? Colors.white
                : Colors.indigo,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: highContrast
                  ? Colors.white
                  : Colors.black,
            ),
          ),
          subtitle: Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: highContrast
                  ? Colors.white
                  : Colors.black87,
              height: 1.3,
            ),
          ),
          value: value,
          onChanged: (newValue) {
            _buttonHaptic();
            onChanged(newValue);
          },
        ),
      ),
    );
  }

  void _showDuplicateWarning(String medTitle) {
    final highContrast =
        _accessibility.highContrast;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor:
          highContrast
              ? Colors.black
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(18),
            side: highContrast
                ? const BorderSide(
              color: Colors.white,
              width: 2,
            )
                : BorderSide.none,
          ),
          title: Text(
            "Medication Already Scanned",
            style: TextStyle(
              color: highContrast
                  ? Colors.white
                  : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            "'$medTitle' was scanned recently.",
            style: TextStyle(
              color: highContrast
                  ? Colors.white
                  : Colors.black87,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _buttonHaptic();

                Navigator.of(context).pop();

                _scanner.resumeLiveScanning();
              },
              child: Text(
                "Cancel",
                style: TextStyle(
                  color: highContrast
                      ? Colors.white
                      : Colors.indigo,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                highContrast
                    ? Colors.yellow
                    : Colors.indigo,
                foregroundColor:
                highContrast
                    ? Colors.black
                    : Colors.white,
              ),
              onPressed: () {
                _buttonHaptic();

                Navigator.of(context).pop();

                _scanner.forceSaveLabel(
                  medTitle,
                );
              },
              child: const Text(
                "Log Anyway",
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BoundingBoxPainter
    extends CustomPainter {
  final DebugFrameInfo frame;
  final bool highContrast;

  _BoundingBoxPainter({
    required this.frame,
    required this.highContrast,
  });

  @override
  void paint(
      Canvas canvas,
      Size size,
      ) {
    if (frame.effectiveWidth <= 0 ||
        frame.effectiveHeight <= 0) {
      return;
    }

    final scaleX =
        size.width / frame.effectiveWidth;

    final scaleY =
        size.height / frame.effectiveHeight;

    // =========================================================================
    // OCR BLOCK BOXES
    // =========================================================================

    final blockPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth =
      highContrast ? 2.5 : 1.5
      ..color = highContrast
          ? Colors.white
          : Colors.yellow;

    for (final box in frame.blockBoxes) {
      final rect = Rect.fromLTRB(
        box.left * scaleX,
        box.top * scaleY,
        box.right * scaleX,
        box.bottom * scaleY,
      );

      canvas.drawRect(
        rect,
        blockPaint,
      );
    }

    // =========================================================================
    // UNION BOX
    // =========================================================================

    if (frame.unionBox != null) {
      final box = frame.unionBox!;

      final rect = Rect.fromLTRB(
        box.left * scaleX,
        box.top * scaleY,
        box.right * scaleX,
        box.bottom * scaleY,
      );

      final unionPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth =
        highContrast ? 6 : 4
        ..color = highContrast
            ? (frame.isWellPositioned
            ? Colors.white
            : Colors.yellow)
            : (frame.isWellPositioned
            ? Colors.green
            : Colors.red);

      canvas.drawRect(
        rect,
        unionPaint,
      );
    }
  }

  @override
  bool shouldRepaint(
      covariant _BoundingBoxPainter oldDelegate,
      ) {
    return oldDelegate.frame != frame ||
        oldDelegate.highContrast !=
            highContrast;
  }
}