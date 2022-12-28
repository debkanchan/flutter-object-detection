import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:touchable/touchable.dart';

import 'coordinates_translator.dart';

class ObjectDetectorPainter extends CustomPainter {
  ObjectDetectorPainter(
    this.context,
    this._objects,
    this.rotation,
    this.absoluteSize,
    this.onSelected,
  );

  final List<DetectedObject> _objects;
  final Size absoluteSize;
  final InputImageRotation rotation;
  final BuildContext context;
  final Function(DetectedObject objectSelected) onSelected;

  @override
  void paint(Canvas canvas, Size size) {
    final touchableCanvas = TouchyCanvas(context, canvas);

    final Paint paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 3.0
      ..color = Colors.white.withOpacity(0.35);

    final Paint background = Paint()..color = const Color(0x99000000);

    for (final DetectedObject detectedObject in _objects) {
      final ParagraphBuilder builder = ParagraphBuilder(
        ParagraphStyle(
          textAlign: TextAlign.center,
          fontSize: 16,
          textDirection: TextDirection.ltr,
        ),
      );

      builder.pushStyle(
        ui.TextStyle(color: Colors.white, background: background),
      );

      for (final Label label in detectedObject.labels) {
        builder.addText(
          '${label.text} ${(label.confidence * 100).truncateToDouble()}\n',
        );
      }

      builder.pop();

      final left = translateX(
        detectedObject.boundingBox.left,
        rotation,
        size,
        absoluteSize,
      );
      final top = translateY(
        detectedObject.boundingBox.top,
        rotation,
        size,
        absoluteSize,
      );
      final right = translateX(
        detectedObject.boundingBox.right,
        rotation,
        size,
        absoluteSize,
      );
      final bottom = translateY(
        detectedObject.boundingBox.bottom,
        rotation,
        size,
        absoluteSize,
      );

      touchableCanvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, top, right, bottom),
          const Radius.circular(12),
        ),
        paint,
        onTapUp: (_) => onSelected(detectedObject),
      );

      touchableCanvas.drawParagraph(
        builder.build()
          ..layout(ParagraphConstraints(
            width: right - left,
          )),
        Offset(left, top + 20),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
