import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../core/image_processor_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../core/database.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>{

  List<CameraDescription> cameras = [];
  CameraController? cameraController;
  bool _captureNextFrame = false;
  final OCRProcess _ocrService = OCRProcess();
  final DatabaseService _dbService = DatabaseService();
  String _scanResult = "Tap the camera to scan";

  @override
  void initState(){
    super.initState();
    _setupCameraController();
    
  }
  @override
  void dispose() {
    cameraController?.dispose();
    super.dispose();
  }

  //UI
  @override
  Widget build(BuildContext context){
    return Scaffold(
      body: _buildUI(),
    );
  }
  
  Widget _buildUI(){
    if (cameraController == null || cameraController?.value.isInitialized == false){
      return const Center(child: CircularProgressIndicator(),);    
    }
    return SafeArea(child: SizedBox.expand(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
            // used expanded and singlechildscroll so the text doesnt overflow
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
            child:ClipRRect(
              child: FittedBox(
                fit: BoxFit.cover,
                alignment: Alignment.center,
                child: SizedBox(
                  //because phone are vertically held, sensor height and width are swapped
                  width: cameraController!.value.previewSize?.height ?? 1 ,
                  height: cameraController!.value.previewSize?.width ?? 1,
                  child: CameraPreview(cameraController!),
                ),
              ),
            ) 
          ),
        
          IconButton(
            onPressed: () {
              setState(() {
                _scanResult = "Scanning...";
                _captureNextFrame = true;
              });
            } , 
            iconSize: 100,            //change button size
            icon: const Icon(
              Icons.camera,
              color: Colors.red,
            ),
          )
        ],
      ),
    )
    ); 
  }

  Future<void> _setupCameraController() async {
    List<CameraDescription> _cameras = await availableCameras();    //put list of cameras of device into _cameras
    if (_cameras.isNotEmpty){               //check if device have cameras
      setState(() {
        cameras = _cameras;         //setting cameras list with the list of cameras from _cameras
        cameraController = CameraController(
          _cameras.first, // <--- first because backcamera (need to optimized this)
          ResolutionPreset.max, 
          enableAudio: false, // turn off microphone 
          imageFormatGroup: Platform.isAndroid 
              ? ImageFormatGroup.yuv420     //if andriod hardcode to change format into yuv420
              : ImageFormatGroup.bgra8888,  //if ios hardcode to change format into BGRA8888
        );
      });
      cameraController?.initialize().then((_) {
        if (!mounted) return; // Standard safety check
        setState((){});
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
            final String result = await _ocrService.scanLabel(rawBytes, image.width, image.height, isAndroid,sensorOrientation);

            //Database logic
            if (result.isNotEmpty){
              //initalized result text and current time
              final newScan = ScannedLabels(text: result, times: DateTime.now().toIso8601String(),);

              //insert into database
              await _dbService.insertLabels(newScan);
              print("Successfully saved to database!");

              final savedLabels = await _dbService.outPutLabels(limitCount: 3); //parameters are optionals, rn limit count: 3 is a test data
              print("--- CURRENT DATABASE LOGS ---");
              for (var label in savedLabels) {
                print("ID: ${label.id} | Text: ${label.text} | Time: ${label.times}");
              }
              print("-----------------------------");
            }
            // ====================================================================================================
            if (mounted) {
              setState(() {
                _scanResult = result.isEmpty ? "No text found." : result;
              });
            }
          } catch (e) {
            if (mounted) {
              setState(() {
                _scanResult = "Error: $e";
              });
            }
          }
        });
      });
    }
  }
}