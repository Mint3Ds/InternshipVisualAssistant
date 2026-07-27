import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:typed_data';
import 'dart:io';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'dart:ui'; // uses the Size feature
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'; //uses the TextRecognizer, RecognizedText features
//------------------------Version 1 ------------------------------------------------------------------------------
// class ImageProcessor{
//   Uint8List processImage(Uint8List rawImageBytes){   //catches raw bytes buffer coming from phone camera
//     final img = cv.imdecode(rawImageBytes, cv.IMREAD_COLOR);   //imdecode receieves raw byte buffer to decode in memory. Structure raw bytes into Matrix format of 2D pixels (with colors)
//     final gray = cv.cvtColor(img, cv.COLOR_BGR2GRAY); //takes the img and applies grayscale algo and put it in gray var.
//     final bgraGray = cv.cvtColor(gray, cv.COLOR_GRAY2BGRA); //recoverting the grayscale image to BGRA (4 channel format) so it will be competible with andriod and IOS. The image is still grayscale


//     // var (success, cleanBytes) = cv.imencode('.jpg', gray);   //compressing gray matrix into .jpg format
//     return bgraGray;
//   }
// }
//=======================================================================================================================
class ImageProcessor {

  //accepts raw bytes and dimensions from the camera sensors and a flag to identify which os we are reading
  Uint8List Imageprocess(Uint8List rawBytes, int width, int height, bool isAndroid) {
    final cv.Mat srcMat;   //initizing var called srcMat
    final cv.Mat grayMat;
    if (isAndroid) {      //checking for andriod 
      srcMat = cv.Mat.fromList((height * 1.5).toInt(), width, cv.MatType.CV_8UC1, rawBytes);   //used 1.5 times height because of andriod 1.5x compressed NV21 format
      grayMat = cv.cvtColor(srcMat, cv.COLOR_YUV2GRAY_NV21);     //grayscaling the image into grayscale NV21 format
    } 
    else {                //checking for IOS
      srcMat = cv.Mat.fromList(height, width, cv.MatType.CV_8UC4, rawBytes); //used BGRA8888 (4 channel format) for IOS
      grayMat = cv.cvtColor(srcMat, cv.COLOR_BGRA2GRAY);         //grayscaling the image into grayscale BGRA format
    }
    
    if (isAndroid){       
      Uint8List yBytes = grayMat.data; // The grayscale image is our Y-plane //Y are one byte per pixel. //uses this one instead of adaptive_thresh because google ML kit uses natural modern LLM
      int uvSize = (width * height) ~/ 2; // NV21 UV-plane size because UV colors are one pair for every 2×2 pixels
    
      Uint8List nv21Bytes = Uint8List(yBytes.length + uvSize);   //nv21 arrary is a combination of Y scale (brightness) and UV(color)

      nv21Bytes.setRange(0, yBytes.length, yBytes); // fill in the beginning till Yscale (yBytes.length) with grayscale
      nv21Bytes.fillRange(yBytes.length, nv21Bytes.length, 128); //fill the rest of the NV21 arrary with UV colors which is 128 (color for grayscale images)
      return nv21Bytes;
    } else{    
    //Converting the 1-channel gray binary image back into 4-channel BGRA format to let both andriod and IOS understasnd
      final finalBgraMat = cv.cvtColor(grayMat, cv.COLOR_GRAY2BGRA);

      return finalBgraMat.data; // Temporary return so it compiles
    }
  }
}

class OCRProcess{
  //declaring instance for image processor
  final ImageProcessor _processor = ImageProcessor();
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin); //used the TextRecognizer with latin script to read english

  //creating a method for scanLabel operations
  Future<String> scanLabel(Uint8List rawBytes,int width,int height,bool isAndroid, int sensorOrientation) async {
    //initlizing a variable with the cleaned image
    Uint8List cleanBytes = _processor.Imageprocess(rawBytes,width,height,isAndroid);

    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation0deg; //basically rotation of your camera
    //inputing data into ML.
    //size - size of data
    //format - NV21 (android) or BGRA8888 (IOS) format 
    //bytesPerRow - BGRA has 4 channel so 4 bytes per pixel
    final metadata = InputImageMetadata(
      size: Size(width.toDouble(), height.toDouble()),
      rotation: rotation,
      format: isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
      bytesPerRow: isAndroid ? width : (width * 4), //4 channel so "* 4"
    );

    //Assemble the InputImage
    final inputImage = InputImage.fromBytes(bytes: cleanBytes, metadata: metadata);

    //Feed the 4 channel grayscale image to the ML kit engine
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

    //Return the raw extracted string back to the UI
    return recognizedText.text;
  
  }
}
// //=============ACTUALLY MAIN=================================================
// Future<void> main() async {
//   // Point directly to the test image
//   final inputImage = InputImage.fromFilePath('D:/Internship/flutter_application_1/img/test1.png');

//   //Initialize the ML Kit engine to read latin
//   final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin); 

//   //Process the image. Used await to pause the code to let the ML process data 
//   print("Scanning image...");
//   final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
//   //Print the extracted text blocks
//   for (TextBlock block in recognizedText.blocks) {
//     print("Found text: ${block.text}");
//   }


//   textRecognizer.close();
//   print("Process completed.");
// }

