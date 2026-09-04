import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:typed_data';
import 'dart:io';
import 'dart:math' show atan2, pi;
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'dart:ui'; // uses the Size feature
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'; //uses the TextRecognizer, RecognizedText features

class ImageProcessor {
  //accepts raw bytes and dimensions from the camera sensors and a flag to identify which os we are reading
  (Uint8List,double) Imageprocess(Uint8List rawBytes, int width, int height, bool isAndroid) {
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

    final enhancedGray = cv.equalizeHist(grayMat); //flattening lighting to reduce glare

    //blur detection (Laplacian Variance)
    final laplacian = cv.laplacian(enhancedGray, cv.MatType.CV_64F);
    
    //get the standard deviation of the edges
    final (mean, stdDev) = cv.meanStdDev(laplacian);
    
    //Square the standard deviation to get the variance blur score
    final double blurScore = stdDev.val[0] * stdDev.val[0];
    
    if (isAndroid){       
      Uint8List yBytes = enhancedGray.data; // The grayscale image is our Y-plane. Y are one byte per pixel. Uses this one instead of adaptive_thresh because google ML kit uses natural modern LLM
      int uvSize = (width * height) ~/ 2; // NV21 UV-plane size because UV colors are one pair for every 2×2 pixels
    
      Uint8List nv21Bytes = Uint8List(yBytes.length + uvSize);   //nv21 arrary is a combination of Y scale (brightness) and UV(color)

      nv21Bytes.setRange(0, yBytes.length, yBytes); // fill in the beginning till Yscale (yBytes.length) with grayscale
      nv21Bytes.fillRange(yBytes.length, nv21Bytes.length, 128); //fill the rest of the NV21 arrary with UV colors which is 128 (color for grayscale images)
      return (nv21Bytes, blurScore);
    } else{    
    //Converting the 1-channel gray binary image back into 4-channel BGRA format to let both andriod and IOS understasnd
      final finalBgraMat = cv.cvtColor(enhancedGray, cv.COLOR_GRAY2BGRA);

      return (finalBgraMat.data,blurScore); // Temporary return so it compiles //need actual IOS device to be tested with.
    }
  }
}

class PositionFeedback { 
  final bool isWellPositioned; 
  final String message; 
  final Rect? boundingBox;  
  final double? areaRatio;  
  final double? offsetXRatio; 
  final double? offsetYRatio;  
  final List<TextBlock> consideredBlocks;
  final double? debugRawAngle; 
  final int? debugBucket; 

  const PositionFeedback( 
    this.isWellPositioned,
    this.message, { 
    this.boundingBox, 
    this.areaRatio, 
    this.offsetXRatio, 
    this.offsetYRatio, 
    this.consideredBlocks = const [], 
    this.debugRawAngle, 
    this.debugBucket, 
  }); 
} 

double? estReadingAngle(List<TextBlock> blocks) {
  double sumX = 0, sumY = 0;
  for (final TextBlock block in blocks) {
    for (final TextLine line in block.lines) {
      final corners = line.cornerPoints;
      if (corners.length < 4) continue; //skips to next line if the text has less than 4 corners 
      final double dxA = (corners[1].x - corners[0].x).toDouble();  //these calculate the movement from 1 corner to another
      final double dyA = (corners[1].y - corners[0].y).toDouble();
      final double dxB = (corners[2].x - corners[1].x).toDouble();
      final double dyB = (corners[2].y - corners[1].y).toDouble();

      final bool aIsLonger = (dxA * dxA + dyA * dyA) >= (dxB * dxB + dyB * dyB);    //using distance formular without the sqrt to see if "direction A" is longer
                              sumX += aIsLonger ? dxA : dxB;                  
                              sumY += aIsLonger ? dyA : dyB;          //compares the horizontal and vertical distance
      } //longer text lines carries more weight in influenceing the angle
  }
  if (sumX == 0 && sumY == 0) return null;
  return atan2(sumY, sumX) * 180 / pi;        //find the angle
}

int normalizedAngle(double angleDegrees) {   //normalized the angles into {0,90,180,270}
  double normalized = angleDegrees % 360;
  if (normalized < 0) normalized += 360;
  return ((normalized / 90).round() % 4) * 90;
}

const double AngleCorrection = 90.0;  // *IMPORTANT* NEED TO ADJUST THIS BY MAKING IT UNIVERSAL!! 
//currently works for samsung A54 5G

class FramePositionAnalyzer { 

  static const double EDGE_MARGIN = 0.03; // within 3% of an edge = "cut off"
  static const double MIN_AREA = 0.03;    // text region < 3% of frame = too far away
  static const double MAX_AREA = 0.65;    // text region > 65% of frame = too close
  static const double CENTER_TOLERANCE = 0.15; // 15% off-center before we ask for a move

  PositionFeedback analyze(RecognizedText recognizedText, int effectiveWidth, int effectiveHeight,) {
  
    final List<TextBlock> centralBlocks = _centralBlocks(recognizedText.blocks, effectiveWidth, effectiveHeight); 

    if (centralBlocks.isEmpty) { 
      return const PositionFeedback( 
      false, 
      "No label detected. Point the camera at the medication label.", 
      ); 
    } //if nothing central detected, return false and a text

    // Union bounding box across the central text blocks only. 
    double left = double.infinity; 
    double top = double.infinity;           
    double right = double.negativeInfinity; 
    double bottom = double.negativeInfinity; 

    for (final TextBlock block in centralBlocks) {      // loop through the central text boxes only
      final box = block.boundingBox;
      if (box.left < left) left = box.left.toDouble();          // checking the far left
      if (box.top < top) top = box.top.toDouble();              // checking the highest top
      if (box.right > right) right = box.right.toDouble();      // checking the far right
      if (box.bottom > bottom) bottom = box.bottom.toDouble();  // checking the lowest bottom
    } 

    final double boxWidth = right - left;   //finding the width of the box
    final double boxHeight = bottom - top;  //finding the height of the box
    if (boxWidth <= 0 || boxHeight <= 0) {  // if no box is found instead only a line
      return const PositionFeedback(
      false, 
        "No label detected. Point the camera at the medication label.",
      ); 
    } 

   
    final Rect unionBox = Rect.fromLTRB(left, top, right, bottom);                        //creates a whole new unionized box with the result from above
    final double areaRatio = (boxWidth * boxHeight) / (effectiveWidth * effectiveHeight); // finding how much (in ratio) of the text box is to the entire camera frame
    final double boxCenterX = left + boxWidth / 2; 
    final double boxCenterY = top + boxHeight / 2; 
    final double offsetXRatio = (boxCenterX - effectiveWidth / 2) / effectiveWidth;       //finds how far the text is horizontal from the center of camera frame
    final double offsetYRatio = (boxCenterY - effectiveHeight / 2) / effectiveHeight;     //same thing but for vertical distance

    //Is the text getting cut off by the edge of the frame? 
    final double marginX = effectiveWidth * EDGE_MARGIN;                 //calculates the horizontal margin by using the camera frame and provided ratio
    final double marginY = effectiveHeight * EDGE_MARGIN;                //same but for vertical margin
    final bool touchesLeft = left <= marginX;                                 //checks if the left side of the unionized text box touches marginX (to tell if its cut off)
    final bool touchesRight = right >= effectiveWidth - marginX;              //same for right side
    final bool touchesTop = top <= marginY;                                   //same for top side
    final bool touchesBottom = bottom >= effectiveHeight - marginY;           //same for buttom size 

    if (touchesLeft || touchesRight || touchesTop || touchesBottom) {         //checks if the textbox gets cut off
      final List<String> dirs = []; 
      if (touchesLeft) dirs.add("left");      // if text gets cut off on the left side then camera needs to turn to the left
      if (touchesRight) dirs.add("right");   
      if (touchesTop) dirs.add("up");      
      if (touchesBottom) dirs.add("down");    
      return PositionFeedback(false, 
        "Label is getting cut off. Move the camera ${dirs.join(' and ')}.",
        boundingBox: unionBox, 
        areaRatio: areaRatio, 
        offsetXRatio: offsetXRatio,
        offsetYRatio: offsetYRatio, 
        consideredBlocks: centralBlocks, 
      ); 
    } 

    // checks if the text is too small or large
    if (areaRatio < MIN_AREA) { 
      return PositionFeedback( 
        false, 
        "Move closer to the label.",
        boundingBox: unionBox, 
        areaRatio: areaRatio, 
        offsetXRatio: offsetXRatio, 
        offsetYRatio: offsetYRatio, 
        consideredBlocks: centralBlocks, 
      ); 
    }else if (areaRatio > MAX_AREA) {
      return PositionFeedback( 
        false, 
        "Move back a little.", 
        boundingBox: unionBox, 
        areaRatio: areaRatio, 
        offsetXRatio: offsetXRatio, 
        offsetYRatio: offsetYRatio, 
        consideredBlocks: centralBlocks, 
      );
    } 

    //check if the text off-center
    final List<String> moveDirs = []; 
    if (offsetXRatio.abs() > CENTER_TOLERANCE) { 
      moveDirs.add(offsetXRatio > 0 ? "right" : "left"); 
    } 
    if (offsetYRatio.abs() > CENTER_TOLERANCE) { 
      moveDirs.add(offsetYRatio > 0 ? "down" : "up"); 
    } 

    if (moveDirs.isNotEmpty) { 
      return PositionFeedback( 
        false, 
        "Center the label — move the camera ${moveDirs.join(' and ')}.", 
        boundingBox: unionBox, 
        areaRatio: areaRatio, 
        offsetXRatio: offsetXRatio, 
        offsetYRatio: offsetYRatio, 
        consideredBlocks: centralBlocks, 
      ); 
    } 

    //checking orentation of object
    final double? angle = estReadingAngle(centralBlocks);
    int? bucket;
    if (angle != null) {
      bucket = normalizedAngle(angle + AngleCorrection);
      if (bucket == 180) {
        return PositionFeedback(
          false,
          "Label looks upside down. Flip it around.",
          boundingBox: unionBox,
          areaRatio: areaRatio,
          offsetXRatio: offsetXRatio,
          offsetYRatio: offsetYRatio,
          consideredBlocks: centralBlocks,
          debugRawAngle: angle,
          debugBucket: bucket,
        );
      } else if (bucket == 90 || bucket == 270) {
        return PositionFeedback(
          false,
          "Label looks sideways. Rotate it so the text is upright.",
          boundingBox: unionBox,
          areaRatio: areaRatio,
          offsetXRatio: offsetXRatio,
          offsetYRatio: offsetYRatio,
          consideredBlocks: centralBlocks,
          debugRawAngle: angle,
          debugBucket: bucket,
        );
      }
    }

    //if every other checks is fine then returns well position.
    return PositionFeedback(
      true, 
      "Well positioned.", 
      boundingBox: unionBox, 
      areaRatio: areaRatio, 
      offsetXRatio: offsetXRatio, 
      offsetYRatio: offsetYRatio, 
      consideredBlocks: centralBlocks, 
      debugRawAngle: angle,
      debugBucket: bucket,
    ); 
  } 

//filters center labels with out of bound background labels 
  static const double CENTRAL_REGION_WIDTH = 0.8; 
  static const double CENTRAL_REGION_HEIGHT = 0.8; 

  List<TextBlock> _centralBlocks(List<TextBlock> blocks, int width, int height) { 
    final double marginX = width * (1 - CENTRAL_REGION_WIDTH) / 2; 
    final double marginY = height * (1 - CENTRAL_REGION_HEIGHT) / 2; 
    final double left = marginX; 
    final double right = width - marginX; 
    final double top = marginY; 
    final double bottom = height - marginY; 

    return blocks.where((TextBlock block) { 
      final Rect box = block.boundingBox; 
      final double centerX = box.left + box.width / 2; 
      final double centerY = box.top + box.height / 2; 
      return centerX >= left && centerX <= right && centerY >= top && centerY <= bottom; 
    }).toList(); 
  } 
} 


String orderedReadingText(List<TextBlock> blocks) {
  final List<TextLine> lines = [
    for (final TextBlock block in blocks) ...block.lines,
  ];

  lines.sort((a, b) {
    final Rect boxA = a.boundingBox;
    final Rect boxB = b.boundingBox;
    // Lines within roughly half a line-height of each other are treated as
    // sitting on the same visual row and ordered left-to-right; otherwise
    // order strictly top-to-bottom.
    final double rowThreshold = (boxA.height + boxB.height) / 4;
    if ((boxA.top - boxB.top).abs() < rowThreshold) {
      return boxA.left.compareTo(boxB.left);
    }
    return boxA.top.compareTo(boxB.top);
  });

  return lines.map((TextLine line) => line.text).join('\n');
}

class OCRProcess{
  //declaring instance for image processor
  final ImageProcessor _processor = ImageProcessor();
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin); //used the TextRecognizer with latin script to read english

  //creating a method for scanLabel operations
  Future<RecognizedText> scanLabel(Uint8List rawBytes,int width,int height,bool isAndroid, int sensorOrientation) async {
    //initlizing a variable with the cleaned image
    final (cleanBytes,blurScore) = _processor.Imageprocess(rawBytes,width,height,isAndroid);

    if (blurScore < 100.0){     // tuned at ResolutionPreset.max, retune if resolution changes
        throw Exception("BLURRY_FRAME");  //Exception is thrown when blurry image is detected
    }

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

    //Return the raw extracted recognized text format (not string) back to the UI
     return recognizedText;
  
  }
}

//this entire function basically takes the RecognizedText from machine ML kit and find the highest height of text line (instead of block).
//because the title usual are the biggest on the labels.
class TitleExtraction {
  String extractTitle(RecognizedText recognizedText) {
    String medName = "";
    double maxLineHeight = 0;

    // Iterate through blocks, and then through individual lines
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        final double lineHeight = line.boundingBox.height;

        // Find the line with the largest physical height (largest font)
        if (lineHeight > maxLineHeight) {
          maxLineHeight = lineHeight;
          medName = line.text;
        }
      }
    }
    return medName.trim().toLowerCase();
  }
}