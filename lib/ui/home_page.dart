import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../core/camera_scanning.dart'; // Import the new controller
import '../core/label_history.dart';  //lets the user view/delete saved titles

//flag that toggles on and off for the guiding boxes for testing purposes
const bool kShowLiveBoundingBoxes = true;

class _BoundingBoxPainter extends CustomPainter { 
  final DebugFrameInfo frame; 
  _BoundingBoxPainter(this.frame); 

  @override
  void paint(Canvas canvas, Size size) { 
    if (frame.effectiveWidth == 0 || frame.effectiveHeight == 0) return;
    // Scale from the OCR's coordinate space (effectiveWidth/Height) into 
    // whatever size this painter is actually being rendered at. 
    final double scaleX = size.width / frame.effectiveWidth; 
    final double scaleY = size.height / frame.effectiveHeight; 

    final Paint blockPaint = Paint() // new
      ..color = const Color(0x99FFEB3B) // new -- translucent yellow, individual detected lines
      ..style = PaintingStyle.stroke // new
      ..strokeWidth = 1.5; // new

    for (final Rect box in frame.blockBoxes) { // new
      canvas.drawRect( // new
        Rect.fromLTRB( // new
          box.left * scaleX, // new
          box.top * scaleY, // new
          box.right * scaleX, // new
          box.bottom * scaleY, // new
        ), // new
        blockPaint, // new
      ); // new
    } // new

    final Rect? union = frame.unionBox; // new
    if (union != null) { // new
      final Paint unionPaint = Paint() // new
        ..color = frame.isWellPositioned // new
            ? const Color(0xFF4CAF50) // new -- green: well positioned
            : const Color(0xFFF44336) // new -- red: needs adjustment
        ..style = PaintingStyle.stroke // new
        ..strokeWidth = 3; // new
      canvas.drawRect( // new
        Rect.fromLTRB( // new
          union.left * scaleX, // new
          union.top * scaleY, // new
          union.right * scaleX, // new
          union.bottom * scaleY, // new
        ), // new
        unionPaint, // new
      ); // new
    } // new
  } // new

  @override // new
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) => true; // new -- new frame data every time, always repaint
} // new

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late ScannerController _scanner;
  String _scanResult = "Tap the camera to scan";
  DebugFrameInfo? _debugFrame; // new -- latest bounding-box/metrics snapshot for the tuning overlay

  @override
  void initState() {
    super.initState();
    
    // Wire up the controller to our UI state
    _scanner = ScannerController(
      onStatusUpdated: (status) {
        if (mounted) {
          setState(() {
            _scanResult = status;
          });
        }
      },
      onWarningTriggered: (medTitle) {
        if (mounted) {
          _showWarningDialog(context, medTitle);
        }
      },
      onCameraInitialized: () {
        if (mounted) {
          setState(() {}); // Refreshes UI to show the camera preview
        }
      },
      // new
      // ScannerController always runs live analysis and calls this on every
      // analyzed frame — kShowLiveBoundingBoxes only decides whether we
      // bother keeping the data around to paint it, so the overlay can be
      // switched off without touching the controller at all.
      onDebugFrame: (frame) { // new
        if (mounted && kShowLiveBoundingBoxes) { // new
          setState(() { // new
            _debugFrame = frame; // new
          }); // new
        } // new
      }, // new
    );

    // Start the camera
    _scanner.initializeCamera();
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scanner"),
        actions: [
          // new -- opens the saved-titles list where entries can be deleted
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: "View saved titles",
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const LabelHistoryPage()),
              );
            },
          ),
        ],
      ),
      body: _buildUI(),
    );
  }

  Widget _buildUI() {
    if (_scanner.cameraController == null || !_scanner.cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return SafeArea(
      child: SizedBox.expand(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Text(
                    _scanResult,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.40,
              width: MediaQuery.sizeOf(context).width * 0.85,
              child: ClipRRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: _scanner.cameraController!.value.previewSize?.height ?? 1,
                    height: _scanner.cameraController!.value.previewSize?.width ?? 1,
                    // new
                    // Stack the overlay directly on top of CameraPreview,
                    // both inside the same sized box, so FittedBox scales
                    // them together and the boxes stay lined up with the
                    // text as the preview is scaled/cropped to fit.
                    child: Stack( // new
                      fit: StackFit.expand, // new
                      children: [ // new
                        CameraPreview(_scanner.cameraController!),
                        if (kShowLiveBoundingBoxes && _debugFrame != null && _scanner.isLiveScanningActive) // new
                          IgnorePointer( // new -- overlay shouldn't intercept taps
                            child: CustomPaint( // new
                              painter: _BoundingBoxPainter(_debugFrame!), // new
                            ), // new
                          ), // new
                      ], // new
                    ), // new
                  ),
                ),
              ),
            ),
            if (kShowLiveBoundingBoxes && _debugFrame != null && _scanner.isLiveScanningActive) // new
              Padding( // new
                padding: const EdgeInsets.symmetric(horizontal: 16), // new
                child: Text( // new
                  // new
                  // Raw numbers behind the position decision — watch these
                  // while moving the label around to pick good thresholds.
                  'area ${_debugFrame!.areaRatio?.toStringAsFixed(3) ?? '-'}  ' // new
                  'dx ${_debugFrame!.offsetXRatio?.toStringAsFixed(3) ?? '-'}  ' // new
                  'dy ${_debugFrame!.offsetYRatio?.toStringAsFixed(3) ?? '-'}  ' // new
                  'angle ${_debugFrame!.debugRawAngle?.toStringAsFixed(1) ?? '-'}  ' // new -- raw estimateReadingAngle(), for tuning kAngleCorrectionDegrees
                  'bucket ${_debugFrame!.debugBucket?.toString() ?? '-'}', // new -- corrected orientation bucket actually used for the decision
                  style: const TextStyle( // new
                    fontSize: 12, // new
                    fontFamily: 'monospace', // new
                    color: Colors.grey, // new
                  ), // new
                ), // new
              ), // new
            // new
            // While live scanning is active, this is the shutter button.
            // Once a capture completes and live scanning pauses (see
            // ScannerController.isLiveScanningActive), it turns into a
            // "Scan Again" button — tapping it clears the frozen overlay
            // and resumes live guidance for the next scan.
            IconButton( // new
              onPressed: () { // new
                if (_scanner.isLiveScanningActive) { // new
                  _scanner.captureNext(); // Just tell the controller to capture
                } else { // new
                  setState(() => _debugFrame = null); // new -- drop the stale frozen overlay
                  _scanner.resumeLiveScanning(); // new
                } // new
              }, // new
              iconSize: 100,
              icon: Icon( // new
                _scanner.isLiveScanningActive ? Icons.camera : Icons.refresh, // new
                color: _scanner.isLiveScanningActive ? Colors.red : Colors.blue, // new
              ), // new
            ), // new
            if (!_scanner.isLiveScanningActive) // new
              const Padding( // new
                padding: EdgeInsets.only(top: 4), // new
                child: Text( // new
                  "Tap to scan again", // new
                  style: TextStyle(fontSize: 12, color: Colors.grey), // new
                ), // new
              ), // new
          ],
        ),
      ),
    );
  }

  void _showWarningDialog(BuildContext context, String medTitle) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Warning"),
          content: Text("You have already scanned '$medTitle' recently. Are you sure you want to log it again?"),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text("Log Anyway"),
              onPressed: () async {
                Navigator.of(context).pop();
                // Ask the controller to force the save
                await _scanner.forceSaveLabel(medTitle);
              },
            ),
          ],
        );
      },
    );
  }
}