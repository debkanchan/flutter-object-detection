import 'dart:async';
import 'dart:io' as io;

import 'package:async/async.dart';
import 'package:camera/camera.dart';
import 'package:demo/painters/object_detector_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:touchable/touchable.dart';
import 'main.dart';

class CameraView extends StatefulWidget {
  const CameraView({super.key});

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  CameraController? _cameraController;
  int _cameraIndex = -1;

  late ObjectDetector _objectDetector;

  final AsyncMemoizer<ObjectDetector> _detectorInitializer = AsyncMemoizer();
  final StreamController<InputImage> _imageStreamController =
      StreamController();
  Completer<List<DetectedObject>> _processingCompleter = Completer()
    ..complete([]);

  @override
  void initState() {
    super.initState();

    _cameraIndex = cameras.indexWhere(
      (element) => element.lensDirection == CameraLensDirection.back,
    );

    if (_cameraIndex != -1) {
      _startCamera();
    }
  }

  @override
  void dispose() {
    _objectDetector.close();
    _stopCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController?.value.isInitialized == false) {
      return Container();
    }

    final size = MediaQuery.of(context).size;
    // calculate scale depending on screen and camera ratios
    // this is actually size.aspectRatio / (1 / camera.aspectRatio)
    // because camera preview size is received as landscape
    // but we're calculating for portrait orientation
    var scale = size.aspectRatio * _cameraController!.value.aspectRatio;

    // to prevent scaling down, invert the value
    if (scale < 1) scale = 1 / scale;

    return Scaffold(
      body: Container(
        color: Colors.black,
        child: FutureBuilder(
            future: _detectorInitializer
                .runOnce(() => _initializeDetector(DetectionMode.stream)),
            builder: (context, snap) {
              if (snap.hasData == false) {
                return Container(
                  color: Colors.black,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              } else {
                _objectDetector = snap.data as ObjectDetector;
              }

              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Transform.scale(
                    scale: scale,
                    child: Center(
                      child: CameraPreview(_cameraController!),
                    ),
                  ),
                  StreamBuilder(
                    stream: _imageStreamController.stream,
                    builder: (context, imageSnapshot) {
                      if (imageSnapshot.hasData == false ||
                          imageSnapshot.connectionState ==
                              ConnectionState.waiting) {
                        return const Center(
                          child: Text(
                            "No Image",
                            style: TextStyle(),
                          ),
                        );
                      }

                      return FutureBuilder<List<DetectedObject>?>(
                        future: _detectObjects(
                            snap.data as ObjectDetector, imageSnapshot.data!),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return CanvasTouchDetector(
                              gesturesToOverride: const [GestureType.onTapUp],
                              builder: (context) {
                                return CustomPaint(
                                  painter: ObjectDetectorPainter(
                                    context,
                                    snapshot.data!,
                                    imageSnapshot
                                        .data!.inputImageData!.imageRotation,
                                    imageSnapshot.data!.inputImageData!.size,
                                    (object) {
                                      final img.Image? originalImage =
                                          img.decodeImage(
                                              imageSnapshot.data!.bytes!);

                                      if (originalImage == null) {
                                        print("Image is null");
                                        return;
                                      }

                                      final croppedImage = img.copyCrop(
                                        originalImage,
                                        object.boundingBox.left.toInt(),
                                        object.boundingBox.top.toInt(),
                                        object.boundingBox.width.toInt(),
                                        object.boundingBox.height.toInt(),
                                      );

                                      showDialog(
                                        context: context,
                                        builder: (context) {
                                          return Image.memory(
                                            croppedImage.getBytes(),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                );
                              },
                            );
                          } else {
                            return const Center(child: Text("No data"));
                          }
                        },
                      );
                    },
                  ),
                ],
              );
            }),
      ),
    );
  }

  void _startCamera() {
    final camera = cameras[_cameraIndex];
    _cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _cameraController?.initialize().then((_) {
      if (!mounted) {
        return;
      }

      _cameraController?.startImageStream((image) {
        final finalImage = _processImage(image);

        if (finalImage != null) {
          _imageStreamController.add(finalImage);
        }
      });
      setState(() {});
    });
  }

  Future _stopCamera() async {
    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();
    _cameraController = null;
  }

  Future<ObjectDetector> _initializeDetector(DetectionMode mode) async {
    // uncomment next lines if you want to use the default model
    // final options = ObjectDetectorOptions(
    //     mode: mode,
    //     classifyObjects: true,
    //     multipleObjects: true);
    // _objectDetector = ObjectDetector(options: options);

    // uncomment next lines if you want to use a local model
    // make sure to add tflite model to assets/ml
    const modelPath = 'assets/ml/object_labeler.tflite';
    String path;

    if (io.Platform.isAndroid) {
      path = 'flutter_assets/$modelPath';
    } else {
      path = '${(await getApplicationSupportDirectory()).path}/$modelPath';
      await io.Directory(dirname(path)).create(recursive: true);
      final file = io.File(path);
      if (!await file.exists()) {
        final byteData = await rootBundle.load(modelPath);
        await file.writeAsBytes(byteData.buffer
            .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
      }
      path = file.path;
    }

    final options = LocalObjectDetectorOptions(
      mode: mode,
      modelPath: path,
      classifyObjects: true,
      multipleObjects: true,
    );

    return ObjectDetector(options: options);
  }

  InputImage? _processImage(CameraImage image) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize =
        Size(image.width.toDouble(), image.height.toDouble());

    final camera = cameras[_cameraIndex];
    final imageRotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (imageRotation == null) return null;

    final inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw);
    if (inputImageFormat == null) return null;

    final planeData = image.planes.map(
      (Plane plane) {
        return InputImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        );
      },
    ).toList();

    final inputImageData = InputImageData(
      size: imageSize,
      imageRotation: imageRotation,
      inputImageFormat: inputImageFormat,
      planeData: planeData,
    );

    final inputImage =
        InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);

    return inputImage;
  }

  Future<List<DetectedObject>?> _detectObjects(
      ObjectDetector detector, InputImage image) async {
    if (_processingCompleter.isCompleted) {
      _processingCompleter = Completer();

      final objects = await detector.processImage(image);

      _processingCompleter.complete(objects);
    }

    return _processingCompleter.future;
  }
}
