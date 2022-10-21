import 'dart:math';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:fl_chart/src/chart/base/axis_chart/axis_chart_extensions.dart';
import 'package:fl_chart/src/chart/base/axis_chart/axis_chart_painter.dart';
import 'package:fl_chart/src/chart/base/base_chart/base_chart_painter.dart';
import 'package:fl_chart/src/extensions/paint_extension.dart';
import 'package:fl_chart/src/extensions/path_extension.dart';
import 'package:fl_chart/src/utils/canvas_wrapper.dart';
import 'package:fl_chart/src/chart/custom_paint/icon_buy_painter.dart';
import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';
import '../../extensions/text_align_extension.dart';
import '../../utils/utils.dart';

/// Paints [LineChartData] in the canvas, it can be used in a [CustomPainter]
class LineChartPainter extends AxisChartPainter<LineChartData> {
  late Paint _barPaint,
      _barAreaPaint,
      _barAreaLinesPaint,
      _clearBarAreaPaint,
      _extraLinesPaint,
      _touchLinePaint,
      _bgTouchTooltipPaint,
      _imagePaint,
      _borderTouchTooltipPaint;

  /// Paints [dataList] into canvas, it is the animating [LineChartData],
  /// [targetData] is the animation's target and remains the same
  /// during animation, then we should use it  when we need to show
  /// tooltips or something like that, because [dataList] is changing constantly.
  ///
  /// [textScale] used for scaling texts inside the chart,
  /// parent can use [MediaQuery.textScaleFactor] to respect
  /// the system's font size.
  LineChartPainter() : super() {
    _barPaint = Paint()..style = PaintingStyle.stroke;

    _barAreaPaint = Paint()..style = PaintingStyle.fill;

    _barAreaLinesPaint = Paint()..style = PaintingStyle.stroke;

    _clearBarAreaPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0x00000000)
      ..blendMode = BlendMode.dstIn;

    _extraLinesPaint = Paint()..style = PaintingStyle.stroke;

    _touchLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black;

    _bgTouchTooltipPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;

    _imagePaint = Paint();

    _borderTouchTooltipPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.transparent
      ..strokeWidth = 1.0;
  }

  /// Paints [LineChartData] into the provided canvas.
  @override
  void paint(BuildContext context, CanvasWrapper canvasWrapper,
      PaintHolder<LineChartData> holder) {
    final data = holder.data;
    if (data.lineBarsData.isEmpty) {
      return;
    }

    if (data.clipData.any) {
      canvasWrapper.saveLayer(
        Rect.fromLTWH(0, -40, canvasWrapper.size.width + 40,
            canvasWrapper.size.height + 40),
        Paint(),
      );

      clipToBorder(canvasWrapper, holder);
    }

    super.paint(context, canvasWrapper, holder);

    for (var betweenBarsData in data.betweenBarsData) {
      drawBetweenBarsArea(canvasWrapper, data, betweenBarsData, holder);
    }

    if (!data.extraLinesData.extraLinesOnTop) {
      drawExtraLines(context, canvasWrapper, holder);
    }

    List<LineIndexDrawingInfo> lineIndexDrawingInfo = [];

    /// draw each line independently on the chart
    for (var i = 0; i < data.lineBarsData.length; i++) {
      final barData = data.lineBarsData[i];

      if (!barData.show) {
        continue;
      }

      drawBarLine(canvasWrapper, barData, holder);
      drawDots(canvasWrapper, barData, holder);

      if (data.extraLinesData.extraLinesOnTop) {
        drawExtraLines(context, canvasWrapper, holder);
      }

      final indicatorsData = data.lineTouchData
          .getTouchedSpotIndicator(barData, barData.showingIndicators);

      if (indicatorsData.length != barData.showingIndicators.length) {
        throw Exception(
            'indicatorsData and touchedSpotOffsets size should be same');
      }

      for (var j = 0; j < barData.showingIndicators.length; j++) {
        final indicatorData = indicatorsData[j];
        final index = barData.showingIndicators[j];
        final spot = barData.spots[index];

        if (indicatorData == null) {
          continue;
        }
        lineIndexDrawingInfo.add(
          LineIndexDrawingInfo(barData, i, spot, index, indicatorData),
        );
      }
    }

    drawTouchedSpotsIndicator(canvasWrapper, lineIndexDrawingInfo, holder);

    if (data.clipData.any) {
      canvasWrapper.restore();
    }

    // Draw touch tooltip on most top spot
    for (var i = 0; i < data.showingTooltipIndicators.length; i++) {
      var tooltipSpots = data.showingTooltipIndicators[i];

      final showingBarSpots = tooltipSpots.showingSpots;
      if (showingBarSpots.isEmpty) {
        continue;
      }
      final barSpots = List<LineBarSpot>.of(showingBarSpots);
      FlSpot topSpot = barSpots[0];
      for (var barSpot in barSpots) {
        if (barSpot.y > topSpot.y) {
          topSpot = barSpot;
        }
      }
      tooltipSpots = ShowingTooltipIndicators(barSpots);

      drawTouchTooltip(
        context,
        canvasWrapper,
        data.lineTouchData.touchTooltipData,
        topSpot,
        tooltipSpots,
        holder,
      );
    }
  }

  @visibleForTesting
  void clipToBorder(
      CanvasWrapper canvasWrapper, PaintHolder<LineChartData> holder) {
    final data = holder.data;
    final viewSize = canvasWrapper.size;
    final clip = data.clipData;
    final border = data.borderData.show ? data.borderData.border : null;

    var left = 0.0;
    var top = 0.0;
    var right = viewSize.width;
    var bottom = viewSize.height;

    if (clip.left) {
      final borderWidth = border?.left.width ?? 0;
      left = borderWidth / 2;
    }
    if (clip.top) {
      final borderWidth = border?.top.width ?? 0;
      top = borderWidth / 2;
    }
    if (clip.right) {
      final borderWidth = border?.right.width ?? 0;
      right = viewSize.width - (borderWidth / 2);
    }
    if (clip.bottom) {
      final borderWidth = border?.bottom.width ?? 0;
      bottom = viewSize.height - (borderWidth / 2);
    }

    canvasWrapper.clipRect(Rect.fromLTRB(left, top, right, bottom));
  }

  @visibleForTesting
  void drawBarLine(CanvasWrapper canvasWrapper, LineChartBarData barData,
      PaintHolder<LineChartData> holder) {
    final viewSize = canvasWrapper.size;
    final barList = barData.spots.splitByNullSpots();

    // paint each sublist that was built above
    // bar is passed in separately from barData
    // because barData is the whole line
    // and bar is a piece of that line
    for (var bar in barList) {
      final barPath = generateBarPath(viewSize, barData, bar, holder);

      final belowBarPath =
          generateBelowBarPath(viewSize, barData, barPath, bar, holder);
      final completelyFillBelowBarPath = generateBelowBarPath(
          viewSize, barData, barPath, bar, holder,
          fillCompletely: true);
      final aboveBarPath =
          generateAboveBarPath(viewSize, barData, barPath, bar, holder);
      final completelyFillAboveBarPath = generateAboveBarPath(
          viewSize, barData, barPath, bar, holder,
          fillCompletely: true);

      drawBelowBar(canvasWrapper, belowBarPath, completelyFillAboveBarPath,
          holder, barData);
      drawAboveBar(canvasWrapper, aboveBarPath, completelyFillBelowBarPath,
          holder, barData);
      drawBarShadow(canvasWrapper, barPath, barData);
      drawBar(canvasWrapper, barPath, barData, holder);
    }
  }

  @visibleForTesting
  void drawBetweenBarsArea(CanvasWrapper canvasWrapper, LineChartData data,
      BetweenBarsData betweenBarsData, PaintHolder<LineChartData> holder) {
    final viewSize = canvasWrapper.size;
    final fromBarData = data.lineBarsData[betweenBarsData.fromIndex];
    final toBarData = data.lineBarsData[betweenBarsData.toIndex];

    final fromBarSplitLines = fromBarData.spots.splitByNullSpots();
    final toBarSplitLines = toBarData.spots.splitByNullSpots();

    if (fromBarSplitLines.length != toBarSplitLines.length) {
      throw ArgumentError(
        "Cannot draw betWeenBarsArea when null spots are inconsistent.",
      );
    }

    for (int i = 0; i < fromBarSplitLines.length; i++) {
      final fromSpots = fromBarSplitLines[i];
      final toSpots = toBarSplitLines[i].reversed.toList();

      final fromBarPath = generateBarPath(
        viewSize,
        fromBarData,
        fromSpots,
        holder,
      );
      final barPath = generateBarPath(
        viewSize,
        toBarData.copyWith(spots: toSpots),
        toSpots,
        holder,
        appendToPath: fromBarPath,
      );
      final left = min(fromBarData.mostLeftSpot.x, toBarData.mostLeftSpot.x);
      final top = max(fromBarData.mostTopSpot.y, toBarData.mostTopSpot.y);
      final right = max(fromBarData.mostRightSpot.x, toBarData.mostRightSpot.x);
      final bottom = min(
        fromBarData.mostBottomSpot.y,
        toBarData.mostBottomSpot.y,
      );
      final aroundRect = Rect.fromLTRB(
        getPixelX(left, viewSize, holder),
        getPixelY(top, viewSize, holder),
        getPixelX(right, viewSize, holder),
        getPixelY(bottom, viewSize, holder),
      );

      drawBetweenBar(
        canvasWrapper,
        barPath,
        betweenBarsData,
        aroundRect,
        holder,
      );
    }
  }

  @visibleForTesting
  void drawDots(
    CanvasWrapper canvasWrapper,
    LineChartBarData barData,
    PaintHolder<LineChartData> holder,
  ) {
    if (!barData.dotData.show || barData.spots.isEmpty) {
      return;
    }
    final viewSize = canvasWrapper.size;

    final barXDelta = getBarLineXLength(barData, viewSize, holder);

    for (var i = 0; i < barData.spots.length; i++) {
      final spot = barData.spots[i];
      if (spot.isNotNull() && barData.dotData.checkToShowDot(spot, barData)) {
        //perhatikan
        final x = getPixelX(spot.x, viewSize, holder);
        final y = getPixelY(spot.y, viewSize, holder);
        final xPercentInLine = (x / barXDelta) * 100;
        final painter =
            barData.dotData.getDotPainter(spot, xPercentInLine, barData, i);

        canvasWrapper.drawDot(painter, spot, Offset(x, y));
      }
    }
  }

  @visibleForTesting
  void drawTouchedSpotsIndicator(
    CanvasWrapper canvasWrapper,
    List<LineIndexDrawingInfo> lineIndexDrawingInfo,
    PaintHolder<LineChartData> holder,
  ) {
    if (lineIndexDrawingInfo.isEmpty) {
      return;
    }
    final viewSize = canvasWrapper.size;

    lineIndexDrawingInfo.sort((a, b) => b.spot.y.compareTo(a.spot.y));

    for (final info in lineIndexDrawingInfo) {
      final barData = info.line;
      final barXDelta = getBarLineXLength(barData, viewSize, holder);

      final data = holder.data;

      final index = info.spotIndex;
      final spot = info.spot;
      final indicatorData = info.indicatorData;

      final touchedSpot = Offset(getPixelX(spot.x, viewSize, holder),
          getPixelY(spot.y, viewSize, holder));

      /// For drawing the dot
      final showingDots = indicatorData.touchedSpotDotData.show;
      var dotHeight = 0.0;
      late FlDotPainter dotPainter;

      if (showingDots) {
        final xPercentInLine = (touchedSpot.dx / barXDelta) * 100;
        dotPainter = indicatorData.touchedSpotDotData
            .getDotPainter(spot, xPercentInLine, barData, index);
        dotHeight = dotPainter.getSize(spot).height;
      }

      /// For drawing the indicator line
      final lineStartY = min(data.maxY,
          max(data.minY, data.lineTouchData.getTouchLineStart(barData, index)));
      final lineEndY = min(data.maxY,
          max(data.minY, data.lineTouchData.getTouchLineEnd(barData, index)));
      final lineStart =
          Offset(touchedSpot.dx, getPixelY(lineStartY, viewSize, holder));
      var lineEnd =
          Offset(touchedSpot.dx, getPixelY(lineEndY, viewSize, holder));

      /// If line end is inside the dot, adjust it so that it doesn't overlap with the dot.
      final dotMinY = touchedSpot.dy - dotHeight / 2;
      final dotMaxY = touchedSpot.dy + dotHeight / 2;
      if (lineEnd.dy > dotMinY && lineEnd.dy < dotMaxY) {
        if (lineStart.dy < lineEnd.dy) {
          lineEnd -= Offset(0, lineEnd.dy - dotMinY);
        } else {
          lineEnd += Offset(0, dotMaxY - lineEnd.dy);
        }
      }

      _touchLinePaint.color = indicatorData.indicatorBelowLine.color;
      _touchLinePaint.strokeWidth =
          indicatorData.indicatorBelowLine.strokeWidth;
      _touchLinePaint.transparentIfWidthIsZero();

      canvasWrapper.drawDashedLine(lineStart, lineEnd, _touchLinePaint,
          indicatorData.indicatorBelowLine.dashArray);

      /// Draw the indicator dot
      if (showingDots) {
        canvasWrapper.drawDot(dotPainter, spot, touchedSpot);
      }
    }
  }

  /// Generates a path, based on [LineChartBarData.isStepChart] for step style, and normal style.
  @visibleForTesting
  Path generateBarPath(Size viewSize, LineChartBarData barData,
      List<FlSpot> barSpots, PaintHolder<LineChartData> holder,
      {Path? appendToPath}) {
    if (barData.isStepLineChart) {
      return generateStepBarPath(viewSize, barData, barSpots, holder,
          appendToPath: appendToPath);
    } else {
      return generateNormalBarPath(viewSize, barData, barSpots, holder,
          appendToPath: appendToPath);
    }
  }

  /// firstly we generate the bar line that we should draw,
  /// then we reuse it to fill below bar space.
  /// there is two type of barPath that generate here,
  /// first one is the sharp corners line on spot connections
  /// second one is curved corners line on spot connections,
  /// and we use isCurved to find out how we should generate it,
  /// If you want to concatenate paths together for creating an area between
  /// multiple bars for example, you can pass the appendToPath
  @visibleForTesting
  Path generateNormalBarPath(Size viewSize, LineChartBarData barData,
      List<FlSpot> barSpots, PaintHolder<LineChartData> holder,
      {Path? appendToPath}) {
    final path = appendToPath ?? Path();
    final size = barSpots.length;

    var temp = const Offset(0.0, 0.0);

    final x = getPixelX(barSpots[0].x, viewSize, holder);
    final y = getPixelY(barSpots[0].y, viewSize, holder);
    if (appendToPath == null) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
    for (var i = 1; i < size; i++) {
      /// CurrentSpot
      final current = Offset(
        getPixelX(barSpots[i].x, viewSize, holder),
        getPixelY(barSpots[i].y, viewSize, holder),
      );

      /// previous spot
      final previous = Offset(
        getPixelX(barSpots[i - 1].x, viewSize, holder),
        getPixelY(barSpots[i - 1].y, viewSize, holder),
      );

      /// next point
      final next = Offset(
        getPixelX(barSpots[i + 1 < size ? i + 1 : i].x, viewSize, holder),
        getPixelY(barSpots[i + 1 < size ? i + 1 : i].y, viewSize, holder),
      );

      final controlPoint1 = previous + temp;

      /// if the isCurved is false, we set 0 for smoothness,
      /// it means we should not have any smoothness then we face with
      /// the sharped corners line
      final smoothness = barData.isCurved ? barData.curveSmoothness : 0.0;
      temp = ((next - previous) / 2) * smoothness;

      if (barData.preventCurveOverShooting) {
        if ((next - current).dy <= barData.preventCurveOvershootingThreshold ||
            (current - previous).dy <=
                barData.preventCurveOvershootingThreshold) {
          temp = Offset(temp.dx, 0);
        }

        if ((next - current).dx <= barData.preventCurveOvershootingThreshold ||
            (current - previous).dx <=
                barData.preventCurveOvershootingThreshold) {
          temp = Offset(0, temp.dy);
        }
      }

      final controlPoint2 = current - temp;

      path.cubicTo(
        controlPoint1.dx,
        controlPoint1.dy,
        controlPoint2.dx,
        controlPoint2.dy,
        current.dx,
        current.dy,
      );
    }

    return path;
  }

  /// generates a `Step Line Chart` bar style path.
  @visibleForTesting
  Path generateStepBarPath(Size viewSize, LineChartBarData barData,
      List<FlSpot> barSpots, PaintHolder<LineChartData> holder,
      {Path? appendToPath}) {
    final path = appendToPath ?? Path();
    final size = barSpots.length;

    final x = getPixelX(barSpots[0].x, viewSize, holder);
    final y = getPixelY(barSpots[0].y, viewSize, holder);
    if (appendToPath == null) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
    for (var i = 0; i < size; i++) {
      /// CurrentSpot
      final current = Offset(
        getPixelX(barSpots[i].x, viewSize, holder),
        getPixelY(barSpots[i].y, viewSize, holder),
      );

      /// next point
      final next = Offset(
        getPixelX(barSpots[i + 1 < size ? i + 1 : i].x, viewSize, holder),
        getPixelY(barSpots[i + 1 < size ? i + 1 : i].y, viewSize, holder),
      );

      final stepDirection = barData.lineChartStepData.stepDirection;

      // middle
      if (current.dy == next.dy) {
        path.lineTo(next.dx, next.dy);
      } else {
        final deltaX = next.dx - current.dx;

        path.lineTo(current.dx + deltaX - (deltaX * stepDirection), current.dy);
        path.lineTo(current.dx + deltaX - (deltaX * stepDirection), next.dy);
        path.lineTo(next.dx, next.dy);
      }
    }

    return path;
  }

  /// it generates below area path using a copy of [barPath],
  /// if cutOffY is provided by the [BarAreaData], it cut the area to the provided cutOffY value,
  /// if [fillCompletely] is true, the cutOffY will be ignored,
  /// and a completely filled path will return,
  @visibleForTesting
  Path generateBelowBarPath(Size viewSize, LineChartBarData barData,
      Path barPath, List<FlSpot> barSpots, PaintHolder<LineChartData> holder,
      {bool fillCompletely = false}) {
    final belowBarPath = Path.from(barPath);

    /// Line To Bottom Right
    var x = getPixelX(barSpots[barSpots.length - 1].x, viewSize, holder);
    double y;
    if (!fillCompletely && barData.belowBarData.applyCutOffY) {
      y = getPixelY(barData.belowBarData.cutOffY, viewSize, holder);
    } else {
      y = viewSize.height;
    }
    belowBarPath.lineTo(x, y);

    /// Line To Bottom Left
    x = getPixelX(barSpots[0].x, viewSize, holder);
    if (!fillCompletely && barData.belowBarData.applyCutOffY) {
      y = getPixelY(barData.belowBarData.cutOffY, viewSize, holder);
    } else {
      y = viewSize.height;
    }
    belowBarPath.lineTo(x, y);

    /// Line To Top Left
    x = getPixelX(barSpots[0].x, viewSize, holder);
    y = getPixelY(barSpots[0].y, viewSize, holder);
    belowBarPath.lineTo(x, y);
    belowBarPath.close();

    return belowBarPath;
  }

  /// it generates above area path using a copy of [barPath],
  /// if cutOffY is provided by the [BarAreaData], it cut the area to the provided cutOffY value,
  /// if [fillCompletely] is true, the cutOffY will be ignored,
  /// and a completely filled path will return,
  @visibleForTesting
  Path generateAboveBarPath(Size viewSize, LineChartBarData barData,
      Path barPath, List<FlSpot> barSpots, PaintHolder<LineChartData> holder,
      {bool fillCompletely = false}) {
    final aboveBarPath = Path.from(barPath);

    /// Line To Top Right
    var x = getPixelX(barSpots[barSpots.length - 1].x, viewSize, holder);
    double y;
    if (!fillCompletely && barData.aboveBarData.applyCutOffY) {
      y = getPixelY(barData.aboveBarData.cutOffY, viewSize, holder);
    } else {
      y = 0.0;
    }
    aboveBarPath.lineTo(x, y);

    /// Line To Top Left
    x = getPixelX(barSpots[0].x, viewSize, holder);
    if (!fillCompletely && barData.aboveBarData.applyCutOffY) {
      y = getPixelY(barData.aboveBarData.cutOffY, viewSize, holder);
    } else {
      y = 0.0;
    }
    aboveBarPath.lineTo(x, y);

    /// Line To Bottom Left
    x = getPixelX(barSpots[0].x, viewSize, holder);
    y = getPixelY(barSpots[0].y, viewSize, holder);
    aboveBarPath.lineTo(x, y);
    aboveBarPath.close();

    return aboveBarPath;
  }

  /// firstly we draw [belowBarPath], then if cutOffY value is provided in [BarAreaData],
  /// [belowBarPath] maybe draw over the main bar line,
  /// then to fix the problem we use [filledAboveBarPath] to clear the above section from this draw.
  @visibleForTesting
  void drawBelowBar(
      CanvasWrapper canvasWrapper,
      Path belowBarPath,
      Path filledAboveBarPath,
      PaintHolder<LineChartData> holder,
      LineChartBarData barData) {
    if (!barData.belowBarData.show) {
      return;
    }

    final viewSize = canvasWrapper.size;

    final belowBarLargestRect = Rect.fromLTRB(
      getPixelX(barData.mostLeftSpot.x, viewSize, holder),
      getPixelY(barData.mostTopSpot.y, viewSize, holder),
      getPixelX(barData.mostRightSpot.x, viewSize, holder),
      viewSize.height,
    );

    final belowBar = barData.belowBarData;
    _barAreaPaint.setColorOrGradient(
      belowBar.color,
      belowBar.gradient,
      belowBarLargestRect,
    );

    if (barData.belowBarData.applyCutOffY) {
      canvasWrapper.saveLayer(
          Rect.fromLTWH(0, 0, viewSize.width, viewSize.height), Paint());
    }

    canvasWrapper.drawPath(belowBarPath, _barAreaPaint);

    // clear the above area that get out of the bar line
    if (barData.belowBarData.applyCutOffY) {
      canvasWrapper.drawPath(filledAboveBarPath, _clearBarAreaPaint);
      canvasWrapper.restore();
    }

    /// draw below spots line
    if (barData.belowBarData.spotsLine.show) {
      for (var spot in barData.spots) {
        if (barData.belowBarData.spotsLine.checkToShowSpotLine(spot)) {
          final from = Offset(
            getPixelX(spot.x, viewSize, holder),
            getPixelY(spot.y, viewSize, holder),
          );

          Offset to;

          // Check applyCutOffY
          if (barData.belowBarData.spotsLine.applyCutOffY &&
              barData.belowBarData.applyCutOffY) {
            to = Offset(
              getPixelX(spot.x, viewSize, holder),
              getPixelY(barData.belowBarData.cutOffY, viewSize, holder),
            );
          } else {
            to = Offset(
              getPixelX(spot.x, viewSize, holder),
              viewSize.height,
            );
          }

          _barAreaLinesPaint.color =
              barData.belowBarData.spotsLine.flLineStyle.color;
          _barAreaLinesPaint.strokeWidth =
              barData.belowBarData.spotsLine.flLineStyle.strokeWidth;
          _barAreaLinesPaint.transparentIfWidthIsZero();

          canvasWrapper.drawDashedLine(from, to, _barAreaLinesPaint,
              barData.belowBarData.spotsLine.flLineStyle.dashArray);
        }
      }
    }
  }

  /// firstly we draw [aboveBarPath], then if cutOffY value is provided in [BarAreaData],
  /// [aboveBarPath] maybe draw over the main bar line,
  /// then to fix the problem we use [filledBelowBarPath] to clear the above section from this draw.
  @visibleForTesting
  void drawAboveBar(
      CanvasWrapper canvasWrapper,
      Path aboveBarPath,
      Path filledBelowBarPath,
      PaintHolder<LineChartData> holder,
      LineChartBarData barData) {
    if (!barData.aboveBarData.show) {
      return;
    }

    final viewSize = canvasWrapper.size;

    final aboveBarLargestRect = Rect.fromLTRB(
      getPixelX(barData.mostLeftSpot.x, viewSize, holder),
      0,
      getPixelX(barData.mostRightSpot.x, viewSize, holder),
      getPixelY(barData.mostBottomSpot.y, viewSize, holder),
    );

    final aboveBar = barData.aboveBarData;
    _barAreaPaint.setColorOrGradient(
      aboveBar.color,
      aboveBar.gradient,
      aboveBarLargestRect,
    );

    if (barData.aboveBarData.applyCutOffY) {
      canvasWrapper.saveLayer(
          Rect.fromLTWH(0, 0, viewSize.width, viewSize.height), Paint());
    }

    canvasWrapper.drawPath(aboveBarPath, _barAreaPaint);

    // clear the above area that get out of the bar line
    if (barData.aboveBarData.applyCutOffY) {
      canvasWrapper.drawPath(filledBelowBarPath, _clearBarAreaPaint);
      canvasWrapper.restore();
    }

    /// draw above spots line
    if (barData.aboveBarData.spotsLine.show) {
      for (var spot in barData.spots) {
        if (barData.aboveBarData.spotsLine.checkToShowSpotLine(spot)) {
          final from = Offset(
            getPixelX(spot.x, viewSize, holder),
            getPixelY(spot.y, viewSize, holder),
          );

          Offset to;

          // Check applyCutOffY
          if (barData.aboveBarData.spotsLine.applyCutOffY &&
              barData.aboveBarData.applyCutOffY) {
            to = Offset(
              getPixelX(spot.x, viewSize, holder),
              getPixelY(barData.aboveBarData.cutOffY, viewSize, holder),
            );
          } else {
            to = Offset(
              getPixelX(spot.x, viewSize, holder),
              0.0,
            );
          }

          _barAreaLinesPaint.color =
              barData.aboveBarData.spotsLine.flLineStyle.color;
          _barAreaLinesPaint.strokeWidth =
              barData.aboveBarData.spotsLine.flLineStyle.strokeWidth;
          _barAreaLinesPaint.transparentIfWidthIsZero();

          canvasWrapper.drawDashedLine(from, to, _barAreaLinesPaint,
              barData.aboveBarData.spotsLine.flLineStyle.dashArray);
        }
      }
    }
  }

  @visibleForTesting
  void drawBetweenBar(
    CanvasWrapper canvasWrapper,
    Path barPath,
    BetweenBarsData betweenBarsData,
    Rect aroundRect,
    PaintHolder<LineChartData> holder,
  ) {
    final viewSize = canvasWrapper.size;

    _barAreaPaint.setColorOrGradient(
      betweenBarsData.color,
      betweenBarsData.gradient,
      aroundRect,
    );

    canvasWrapper.saveLayer(
        Rect.fromLTWH(0, 0, viewSize.width, viewSize.height), Paint());
    canvasWrapper.drawPath(barPath, _barAreaPaint);

    // clear the above area that get out of the bar line
    canvasWrapper.restore();
  }

  /// draw the main bar line's shadow by the [barPath]
  @visibleForTesting
  void drawBarShadow(
      CanvasWrapper canvasWrapper, Path barPath, LineChartBarData barData) {
    if (!barData.show || barData.shadow.color.opacity == 0.0) {
      return;
    }

    _barPaint.strokeCap =
        barData.isStrokeCapRound ? StrokeCap.round : StrokeCap.butt;
    _barPaint.strokeJoin =
        barData.isStrokeJoinRound ? StrokeJoin.round : StrokeJoin.miter;
    _barPaint.color = barData.shadow.color;
    _barPaint.shader = null;
    _barPaint.strokeWidth = barData.barWidth;
    _barPaint.color = barData.shadow.color;
    _barPaint.maskFilter = MaskFilter.blur(BlurStyle.normal,
        Utils().convertRadiusToSigma(barData.shadow.blurRadius));

    barPath = barPath.toDashedPath(barData.dashArray);

    barPath = barPath.shift(barData.shadow.offset);

    canvasWrapper.drawPath(
      barPath,
      _barPaint,
    );
  }

  /// draw the main bar line by the [barPath]
  @visibleForTesting
  void drawBar(
    CanvasWrapper canvasWrapper,
    Path barPath,
    LineChartBarData barData,
    PaintHolder<LineChartData> holder,
  ) {
    if (!barData.show) {
      return;
    }
    final viewSize = canvasWrapper.size;

    _barPaint.strokeCap =
        barData.isStrokeCapRound ? StrokeCap.round : StrokeCap.butt;
    _barPaint.strokeJoin =
        barData.isStrokeJoinRound ? StrokeJoin.round : StrokeJoin.miter;

    final rectAroundTheLine = Rect.fromLTRB(
      getPixelX(barData.mostLeftSpot.x, viewSize, holder),
      getPixelY(barData.mostTopSpot.y, viewSize, holder),
      getPixelX(barData.mostRightSpot.x, viewSize, holder),
      getPixelY(barData.mostBottomSpot.y, viewSize, holder),
    );
    _barPaint.setColorOrGradient(
      barData.color,
      barData.gradient,
      rectAroundTheLine,
    );

    _barPaint.maskFilter = null;
    _barPaint.strokeWidth = barData.barWidth;
    _barPaint.transparentIfWidthIsZero();

    barPath = barPath.toDashedPath(barData.dashArray);
    canvasWrapper.drawPath(barPath, _barPaint);
  }

  @visibleForTesting
  void drawExtraLines(BuildContext context, CanvasWrapper canvasWrapper,
      PaintHolder<LineChartData> holder) {
    final data = holder.data;
    final viewSize = canvasWrapper.size;

    if (data.extraLinesData.horizontalLines.isNotEmpty) {
      for (var line in data.extraLinesData.horizontalLines) {
        final from = Offset(0.0, getPixelY(line.y, viewSize, holder));
        final to = Offset(viewSize.width, getPixelY(line.y, viewSize, holder));

        _extraLinesPaint.color = line.color;
        _extraLinesPaint.strokeWidth = line.strokeWidth;
        _extraLinesPaint.transparentIfWidthIsZero();

        canvasWrapper.drawDashedLine(
            from, to, _extraLinesPaint, line.dashArray);

        if (line.sizedPicture != null) {
          final centerX = line.sizedPicture!.width / 2;
          final centerY = line.sizedPicture!.height / 2;
          final xPosition = centerX;
          final yPosition = to.dy - centerY;

          canvasWrapper.save();
          canvasWrapper.translate(xPosition, yPosition);
          canvasWrapper.drawPicture(line.sizedPicture!.picture);
          canvasWrapper.restore();
        }

        if (line.image != null) {
          final centerX = line.image!.width / 2;
          final centerY = line.image!.height / 2;
          final centeredImageOffset = Offset(centerX, to.dy - centerY);
          canvasWrapper.drawImage(
              line.image!, centeredImageOffset, _imagePaint);
        }

        if (line.label.show) {
          final label = line.label;
          final style =
              TextStyle(fontSize: 11, color: line.color).merge(label.style);
          final padding = label.padding as EdgeInsets;

          final span = TextSpan(
            text: label.labelResolver(line),
            style: Utils().getThemeAwareTextStyle(context, style),
          );

          final tp = TextPainter(
            text: span,
            textDirection: TextDirection.ltr,
          );

          tp.layout();
          canvasWrapper.drawText(
              tp,
              label.alignment.withinRect(
                Rect.fromLTRB(
                  from.dx + padding.left,
                  from.dy - padding.bottom - tp.height,
                  to.dx - padding.right - tp.width,
                  to.dy + padding.top,
                ),
              ));
        }
      }
    }

    if (data.extraLinesData.verticalLines.isNotEmpty) {
      for (var line in data.extraLinesData.verticalLines) {
        final from = Offset(getPixelX(line.x, viewSize, holder), 0.0);
        final to = Offset(getPixelX(line.x, viewSize, holder), viewSize.height);

        _extraLinesPaint.color = line.color;
        _extraLinesPaint.strokeWidth = line.strokeWidth;
        _extraLinesPaint.transparentIfWidthIsZero();

        canvasWrapper.drawDashedLine(
            from, to, _extraLinesPaint, line.dashArray);

        if (line.sizedPicture != null) {
          final centerX = line.sizedPicture!.width / 2;
          final centerY = line.sizedPicture!.height / 2;
          final xPosition = to.dx - centerX;
          final yPosition = viewSize.height - centerY;

          canvasWrapper.save();
          canvasWrapper.translate(xPosition, yPosition);
          canvasWrapper.drawPicture(line.sizedPicture!.picture);
          canvasWrapper.restore();
        }
        if (line.image != null) {
          final centerX = line.image!.width / 2;
          final centerY = line.image!.height / 2;
          final centeredImageOffset =
              Offset(to.dx - centerX, viewSize.height - centerY);
          canvasWrapper.drawImage(
              line.image!, centeredImageOffset, _imagePaint);
        }

        if (line.label.show) {
          final label = line.label;
          final style =
              TextStyle(fontSize: 11, color: line.color).merge(label.style);
          final padding = label.padding as EdgeInsets;

          final span = TextSpan(
            text: label.labelResolver(line),
            style: Utils().getThemeAwareTextStyle(context, style),
          );

          final tp = TextPainter(
            text: span,
            textDirection: TextDirection.ltr,
          );

          tp.layout();

          canvasWrapper.drawText(
            tp,
            label.alignment.withinRect(
              Rect.fromLTRB(
                to.dx - padding.right - tp.width,
                from.dy + padding.top,
                from.dx + padding.left,
                to.dy - padding.bottom,
              ),
            ),
          );
        }
      }
    }
  }

  @visibleForTesting
  void drawTouchTooltip(
      BuildContext context,
      CanvasWrapper canvasWrapper,
      LineTouchTooltipData tooltipData,
      FlSpot showOnSpot,
      ShowingTooltipIndicators showingTooltipSpots,
      PaintHolder<LineChartData> holder) {
    final viewSize = canvasWrapper.size;

    const textsBelowMargin = 4;

    /// creating TextPainters to calculate the width and height of the tooltip
    final drawingTextPainters = <TextPainter>[];

    final tooltipItems =
        tooltipData.getTooltipItems(showingTooltipSpots.showingSpots);
    if (tooltipItems.length != showingTooltipSpots.showingSpots.length) {
      throw Exception('tooltipItems and touchedSpots size should be same');
    }

    for (var i = 0; i < showingTooltipSpots.showingSpots.length; i++) {
      final tooltipItem = tooltipItems[i];
      if (tooltipItem == null) {
        continue;
      }

      final span = TextSpan(
        style: Utils().getThemeAwareTextStyle(context, tooltipItem.textStyle),
        text: tooltipItem.text,
        children: tooltipItem.children,
      );

      final tp = TextPainter(
          text: span,
          textAlign: tooltipItem.textAlign,
          textDirection: tooltipItem.textDirection,
          textScaleFactor: holder.textScale);
      tp.layout(maxWidth: tooltipData.maxContentWidth);
      drawingTextPainters.add(tp);
    }
    if (drawingTextPainters.isEmpty) {
      return;
    }

    /// biggerWidth
    /// some texts maybe larger, then we should
    /// draw the tooltip' width as wide as biggerWidth
    ///
    /// sumTextsHeight
    /// sum up all Texts height, then we should
    /// draw the tooltip's height as tall as sumTextsHeight
    var biggerWidth = 0.0;
    var sumTextsHeight = 0.0;
    for (var tp in drawingTextPainters) {
      if (tp.width > biggerWidth) {
        biggerWidth = tp.width;
      }
      sumTextsHeight += tp.height;
    }
    sumTextsHeight += (drawingTextPainters.length - 1) * textsBelowMargin;

    /// if we have multiple bar lines,
    /// there are more than one FlCandidate on touch area,
    /// we should get the most top FlSpot Offset to draw the tooltip on top of it
    final mostTopOffset = Offset(
      getPixelX(showOnSpot.x, viewSize, holder),
      getPixelY(showOnSpot.y, viewSize, holder),
    );

    final tooltipWidth = biggerWidth + tooltipData.tooltipPadding.horizontal;
    final tooltipHeight = sumTextsHeight + tooltipData.tooltipPadding.vertical;

    double tooltipTopPosition;
    if (tooltipData.showOnTopOfTheChartBoxArea) {
      tooltipTopPosition = 0 - tooltipHeight - tooltipData.tooltipMargin;
    } else {
      tooltipTopPosition =
          mostTopOffset.dy - tooltipHeight - tooltipData.tooltipMargin;
    }

    /// draw the background rect with rounded radius
    var rect = Rect.fromLTWH(
      mostTopOffset.dx - (tooltipWidth / 2),
      tooltipTopPosition,
      tooltipWidth,
      tooltipHeight,
    );

    if (tooltipData.fitInsideHorizontally) {
      if (rect.left < 0) {
        final shiftAmount = 0 - rect.left;
        rect = Rect.fromLTRB(
          rect.left + shiftAmount,
          rect.top,
          rect.right + shiftAmount,
          rect.bottom,
        );
      }

      if (rect.right > viewSize.width) {
        final shiftAmount = rect.right - viewSize.width;
        rect = Rect.fromLTRB(
          rect.left - shiftAmount,
          rect.top,
          rect.right - shiftAmount,
          rect.bottom,
        );
      }
    }

    if (tooltipData.fitInsideVertically) {
      if (rect.top < 0) {
        final shiftAmount = 0 - rect.top;
        rect = Rect.fromLTRB(
          rect.left,
          rect.top + shiftAmount,
          rect.right,
          rect.bottom + shiftAmount,
        );
      }

      if (rect.bottom > viewSize.height) {
        final shiftAmount = rect.bottom - viewSize.height;
        rect = Rect.fromLTRB(
          rect.left,
          rect.top - shiftAmount,
          rect.right,
          rect.bottom - shiftAmount,
        );
      }
    }

    final radius = Radius.circular(tooltipData.tooltipRoundedRadius);
    final roundedRect = RRect.fromRectAndCorners(rect,
        topLeft: radius,
        topRight: radius,
        bottomLeft: radius,
        bottomRight: radius);
    _bgTouchTooltipPaint.color = tooltipData.tooltipBgColor;

    final rotateAngle = tooltipData.rotateAngle;
    final rectRotationOffset =
        Offset(0, Utils().calculateRotationOffset(rect.size, rotateAngle).dy);
    final rectDrawOffset = Offset(roundedRect.left, roundedRect.top);

    final textRotationOffset =
        Utils().calculateRotationOffset(rect.size, rotateAngle);

    if (tooltipData.tooltipBorder != BorderSide.none) {
      _borderTouchTooltipPaint.color = tooltipData.tooltipBorder.color;
      _borderTouchTooltipPaint.strokeWidth = tooltipData.tooltipBorder.width;
    }

    // canvasWrapper.drawRotated(
    //   size: rect.size,
    //   rotationOffset: rectRotationOffset,
    //   drawOffset: rectDrawOffset,
    //   angle: rotateAngle,
    //   drawCallback: () {
    //     canvasWrapper.drawRRect(roundedRect, _bgTouchTooltipPaint);
    //     canvasWrapper.drawRRect(roundedRect, _borderTouchTooltipPaint);
    //   },
    // );

    //HERE MAN
    // final Path complexPathToDraw = parseSvgPathData("M159.25,238.29H142.49q-3.63,0-5.18-1.62c-1-1.09-1.55-2.82-1.55-5.19V190.25q0-3.62,1.59-5.21t5.14-1.6h17.77a41.9,41.9,0,0,1,6.81.49,14.65,14.65,0,0,1,5.16,1.87,13.61,13.61,0,0,1,3.45,2.94,12.91,12.91,0,0,1,2.28,3.93,13.21,13.21,0,0,1,.78,4.54q0,8.23-8.23,12,10.81,3.44,10.82,13.39a15.08,15.08,0,0,1-2.36,8.29,14.09,14.09,0,0,1-6.36,5.44,22.24,22.24,0,0,1-5.76,1.48A58.17,58.17,0,0,1,159.25,238.29Zm-12.38-46.5V206h10.18a20.23,20.23,0,0,0,6.41-.79,6.11,6.11,0,0,0,3.46-3,6.7,6.7,0,0,0,.94-3.52q0-4.15-3-5.52t-9-1.36Zm11.56,22.15H146.87v16H158.8q11.26,0,11.27-8.12c0-2.77-1-4.78-2.92-6S162.3,213.94,158.43,213.94Z");
    // final Path complexPathToDraw2 = parseSvgPathData("M112.72,92.4c4,0,8.11.06,12.15-.07,1.74-.06,2.31.36,2.29,2.27-.1,10.63-.06,21.28,0,31.92,0,.17,0,.34,0,.51v31.91a59.47,59.47,0,1,0,61.94-.54q.06-32.15,0-64.29c0-1.57.57-1.75,1.86-1.73,4.2.07,8.41,0,12.61,0,3.27,0,5.86-1.22,7.17-4.41s.27-5.91-2.05-8.27Q186.81,57.41,165,35.09c-4.23-4.31-9.57-4.3-13.8,0Q129.36,57.4,107.57,79.74c-2.32,2.36-3.36,5.06-2,8.27S109.45,92.42,112.72,92.4Zm98.29,117A52.47,52.47,0,1,1,158.54,157,52.53,52.53,0,0,1,211,209.42ZM113.14,84q21.31-21.84,42.65-43.64c2-2,2.71-2,4.75.11q21.18,21.66,42.32,43.33c.37.38,1.11.63.83,1.52-4.89,0-9.77,0-14.66,0a6.73,6.73,0,0,0-6.77,6.55c-.07.86,0,1.72,0,2.58q0,30.18,0,60.37a59.46,59.46,0,0,0-48.2.37V122.58h0q0-14.7,0-29.42c0-5.11-2.69-7.79-7.67-7.81H112.06C112.59,84.7,112.84,84.33,113.14,84Z");
    // canvasWrapper.drawPath(complexPathToDraw, Paint()..color = Colors.redAccent);
    // canvasWrapper.drawPath(complexPathToDraw2, Paint());




    //surya
    double padX = 0;
    double padY = -20;
    double xOffset = rectDrawOffset.dx-padX;
    double yOffset = rectDrawOffset.dy-padY;
    Size size = Size(50, 50);
    Offset offset = Offset(20,20);

    //print('offset x ${offset.dx} y ${offset.dy}');

    // Paint paint_0_fill = Paint()..style=PaintingStyle.fill;
    // paint_0_fill.color = Color(0xffffffff).withOpacity(1.0);
    // canvasWrapper.drawCircle(Offset((size.width*0.5225667)+xOffset,size.height*0.7116667+yOffset),size.width*0.1827000,paint_0_fill);
    //
    // Path path_1 = Path();
    // path_1.moveTo(size.width*0.5308333+xOffset,size.height*0.7943000);
    // path_1.lineTo(size.width*0.4749667,size.height*0.7943000);
    // path_1.quadraticBezierTo(size.width*0.4628667,size.height*0.7943000,size.width*0.4577000,size.height*0.7889000);
    // path_1.cubicTo(size.width*0.4543667,size.height*0.7852667,size.width*0.4525333,size.height*0.7795000,size.width*0.4525333,size.height*0.7716000);
    // path_1.lineTo(size.width*0.4525333,size.height*0.6341667);
    // path_1.quadraticBezierTo(size.width*0.4525333,size.height*0.6221000,size.width*0.4578333,size.height*0.6168000);
    // path_1.quadraticBezierTo(size.width*0.4631333,size.height*0.6115000,size.width*0.4749667,size.height*0.6114667);
    // path_1.lineTo(size.width*0.5342000,size.height*0.6114667);
    // path_1.arcToPoint(Offset(size.width*0.5569000,size.height*0.6131000),radius: Radius.elliptical(size.width*0.1396667, size.height*0.1396667),rotation: 0 ,largeArc: false,clockwise: true);
    // path_1.arcToPoint(Offset(size.width*0.5741000,size.height*0.6193333),radius: Radius.elliptical(size.width*0.04883333, size.height*0.04883333),rotation: 0 ,largeArc: false,clockwise: true);
    // path_1.arcToPoint(Offset(size.width*0.5856000,size.height*0.6291333),radius: Radius.elliptical(size.width*0.04536667, size.height*0.04536667),rotation: 0 ,largeArc: false,clockwise: true);
    // path_1.arcToPoint(Offset(size.width*0.5932000,size.height*0.6422333),radius: Radius.elliptical(size.width*0.04303333, size.height*0.04303333),rotation: 0 ,largeArc: false,clockwise: true);
    // path_1.arcToPoint(Offset(size.width*0.5958000,size.height*0.6573667),radius: Radius.elliptical(size.width*0.04403333, size.height*0.04403333),rotation: 0 ,largeArc: false,clockwise: true);
    // path_1.quadraticBezierTo(size.width*0.5958000,size.height*0.6848000,size.width*0.5683667,size.height*0.6973667);
    // path_1.quadraticBezierTo(size.width*0.6044000,size.height*0.7088333,size.width*0.6044333,size.height*0.7420000);
    // path_1.arcToPoint(Offset(size.width*0.5965667,size.height*0.7696333),radius: Radius.elliptical(size.width*0.05026667, size.height*0.05026667),rotation: 0 ,largeArc: false,clockwise: true);
    // path_1.arcToPoint(Offset(size.width*0.5753667,size.height*0.7877667),radius: Radius.elliptical(size.width*0.04696667, size.height*0.04696667),rotation: 0 ,largeArc: false,clockwise: true);
    // path_1.arcToPoint(Offset(size.width*0.5561667,size.height*0.7927000),radius: Radius.elliptical(size.width*0.07413333, size.height*0.07413333),rotation: 0 ,largeArc: false,clockwise: true);
    // path_1.arcToPoint(Offset(size.width*0.5308333,size.height*0.7943000),radius: Radius.elliptical(size.width*0.1939000, size.height*0.1939000),rotation: 0 ,largeArc: false,clockwise: true);
    // path_1.close();
    // path_1.moveTo(size.width*0.4895667,size.height*0.6393000);
    // path_1.lineTo(size.width*0.4895667,size.height*0.6866667);
    // path_1.lineTo(size.width*0.5235000,size.height*0.6866667);
    // path_1.arcToPoint(Offset(size.width*0.5448667,size.height*0.6840333),radius: Radius.elliptical(size.width*0.06743333, size.height*0.06743333),rotation: 0 ,largeArc: false,clockwise: false);
    // path_1.arcToPoint(Offset(size.width*0.5564000,size.height*0.6740333),radius: Radius.elliptical(size.width*0.02036667, size.height*0.02036667),rotation: 0 ,largeArc: false,clockwise: false);
    // path_1.arcToPoint(Offset(size.width*0.5595333,size.height*0.6623000),radius: Radius.elliptical(size.width*0.02233333, size.height*0.02233333),rotation: 0 ,largeArc: false,clockwise: false);
    // path_1.quadraticBezierTo(size.width*0.5595333,size.height*0.6484667,size.width*0.5495333,size.height*0.6439000);
    // path_1.quadraticBezierTo(size.width*0.5395333,size.height*0.6393333,size.width*0.5195333,size.height*0.6393667);
    // path_1.close();
    // path_1.moveTo(size.width*0.5281000,size.height*0.7131333);
    // path_1.lineTo(size.width*0.4895667,size.height*0.7131333);
    // path_1.lineTo(size.width*0.4895667,size.height*0.7664667);
    // path_1.lineTo(size.width*0.5293333,size.height*0.7664667);
    // path_1.quadraticBezierTo(size.width*0.5668667,size.height*0.7664667,size.width*0.5669000,size.height*0.7394000);
    // path_1.cubicTo(size.width*0.5669000,size.height*0.7301667,size.width*0.5635667,size.height*0.7234667,size.width*0.5571667,size.height*0.7194000);
    // path_1.cubicTo(size.width*0.5507667,size.height*0.7153333,size.width*0.5410000,size.height*0.7131333,size.width*0.5281000,size.height*0.7131333);
    // path_1.close();
    //
    // Paint paint_1_stroke = Paint()..style=PaintingStyle.stroke..strokeWidth=2;
    // paint_1_stroke.color=Color(0xffff1cf7).withOpacity(1.0);
    // canvasWrapper.drawPath(path_1,paint_1_stroke);
    //
    // Paint paint_1_fill = Paint()..style=PaintingStyle.fill;
    // paint_1_fill.color = Color(0xffff1cf7).withOpacity(1.0);
    // canvasWrapper.drawPath(path_1,paint_1_fill);
    //
    // Path path_2 = Path();
    // path_2.moveTo(size.width*0.3757333,size.height*0.3080000);
    // path_2.cubicTo(size.width*0.3890667,size.height*0.3080000,size.width*0.4027667,size.height*0.3082000,size.width*0.4162333,size.height*0.3077667);
    // path_2.cubicTo(size.width*0.4220333,size.height*0.3075667,size.width*0.4239333,size.height*0.3089667,size.width*0.4238667,size.height*0.3153333);
    // path_2.cubicTo(size.width*0.4235333,size.height*0.3507667,size.width*0.4236667,size.height*0.3862667,size.width*0.4238667,size.height*0.4217333);
    // path_2.cubicTo(size.width*0.4238667,size.height*0.4223000,size.width*0.4238667,size.height*0.4228667,size.width*0.4238667,size.height*0.4234333);
    // path_2.lineTo(size.width*0.4238667,size.height*0.5298000);
    // path_2.arcToPoint(Offset(size.width*0.6303333,size.height*0.5280000),radius: Radius.elliptical(size.width*0.1982333, size.height*0.1982333),rotation: 0 ,largeArc: true,clockwise: false);
    // path_2.quadraticBezierTo(size.width*0.6305333,size.height*0.4208333,size.width*0.6303333,size.height*0.3137000);
    // path_2.cubicTo(size.width*0.6303333,size.height*0.3084667,size.width*0.6322333,size.height*0.3078667,size.width*0.6365333,size.height*0.3079333);
    // path_2.cubicTo(size.width*0.6505333,size.height*0.3081667,size.width*0.6645667,size.height*0.3079333,size.width*0.6785667,size.height*0.3079333);
    // path_2.cubicTo(size.width*0.6894667,size.height*0.3079333,size.width*0.6981000,size.height*0.3038667,size.width*0.7024667,size.height*0.2932333);
    // path_2.cubicTo(size.width*0.7068333,size.height*0.2826000,size.width*0.7033667,size.height*0.2735333,size.width*0.6956333,size.height*0.2656667);
    // path_2.quadraticBezierTo(size.width*0.6227000,size.height*0.1913667,size.width*0.5500000,size.height*0.1169667);
    // path_2.cubicTo(size.width*0.5359000,size.height*0.1026000,size.width*0.5181000,size.height*0.1026333,size.width*0.5040000,size.height*0.1169667);
    // path_2.quadraticBezierTo(size.width*0.4312000,size.height*0.1913333,size.width*0.3585667,size.height*0.2658000);
    // path_2.cubicTo(size.width*0.3508333,size.height*0.2736667,size.width*0.3473667,size.height*0.2826667,size.width*0.3519000,size.height*0.2933667);
    // path_2.cubicTo(size.width*0.3564333,size.height*0.3040667,size.width*0.3648333,size.height*0.3080667,size.width*0.3757333,size.height*0.3080000);
    // path_2.close();
    // path_2.moveTo(size.width*0.7033667,size.height*0.6980000);
    // path_2.arcToPoint(Offset(size.width*0.5284667,size.height*0.5233333),radius: Radius.elliptical(size.width*0.1749000, size.height*0.1749000),rotation: 0 ,largeArc: true,clockwise: true);
    // path_2.arcToPoint(Offset(size.width*0.7033333,size.height*0.6980667),radius: Radius.elliptical(size.width*0.1751000, size.height*0.1751000),rotation: 0 ,largeArc: false,clockwise: true);
    // path_2.close();
    // path_2.moveTo(size.width*0.3771333,size.height*0.2800000);
    // path_2.quadraticBezierTo(size.width*0.4481667,size.height*0.2072000,size.width*0.5193000,size.height*0.1345333);
    // path_2.cubicTo(size.width*0.5259667,size.height*0.1278667,size.width*0.5283333,size.height*0.1278667,size.width*0.5351333,size.height*0.1349000);
    // path_2.quadraticBezierTo(size.width*0.6057333,size.height*0.2071000,size.width*0.6762000,size.height*0.2793333);
    // path_2.cubicTo(size.width*0.6774333,size.height*0.2806000,size.width*0.6799000,size.height*0.2814333,size.width*0.6789667,size.height*0.2844000);
    // path_2.cubicTo(size.width*0.6626667,size.height*0.2844000,size.width*0.6464000,size.height*0.2844000,size.width*0.6301000,size.height*0.2844000);
    // path_2.arcToPoint(Offset(size.width*0.6075333,size.height*0.3062333),radius: Radius.elliptical(size.width*0.02243333, size.height*0.02243333),rotation: 0 ,largeArc: false,clockwise: false);
    // path_2.cubicTo(size.width*0.6073000,size.height*0.3091000,size.width*0.6075333,size.height*0.3119667,size.width*0.6075333,size.height*0.3148333);
    // path_2.quadraticBezierTo(size.width*0.6075333,size.height*0.4154333,size.width*0.6075333,size.height*0.5160667);
    // path_2.arcToPoint(Offset(size.width*0.4468667,size.height*0.5173000),radius: Radius.elliptical(size.width*0.1982000, size.height*0.1982000),rotation: 0 ,largeArc: false,clockwise: false);
    // path_2.lineTo(size.width*0.4468667,size.height*0.4086000);
    // path_2.lineTo(size.width*0.4468667,size.height*0.4086000);
    // path_2.quadraticBezierTo(size.width*0.4468667,size.height*0.3596000,size.width*0.4468667,size.height*0.3105333);
    // path_2.cubicTo(size.width*0.4468667,size.height*0.2935000,size.width*0.4379000,size.height*0.2845667,size.width*0.4213000,size.height*0.2845000);
    // path_2.lineTo(size.width*0.3735333,size.height*0.2845000);
    // path_2.cubicTo(size.width*0.3753000,size.height*0.2823333,size.width*0.3761333,size.height*0.2811000,size.width*0.3771333,size.height*0.2800000);
    // path_2.close();
    //
    // Paint paint_2_stroke = Paint()..style=PaintingStyle.stroke..strokeWidth=2;
    // paint_2_stroke.color=Color(0xffff1cf7).withOpacity(1.0);
    // canvasWrapper.drawPath(path_2,paint_2_stroke);
    //
    // Paint paint_2_fill = Paint()..style=PaintingStyle.fill;
    // paint_2_fill.color = Color(0xffff1cf7).withOpacity(1.0);
    // canvasWrapper.drawPath(path_2,paint_2_fill);



    Canvas svgCanvas = canvasWrapper.canvas;
    svgCanvas.translate(xOffset, yOffset);
    var svgRoot= holder.data.lineTouchData.iconBuySvg!;

    // Size svgSize = svgRoot.viewport.size;
    // var matrix = Matrix4.identity();
    // matrix.scale(100 / svgSize.width, 100 / svgSize.height);
    //svgCanvas.transform(matrix.storage);

    ui.Picture svgPicture = svgRoot.toPicture(size:Size(40,40));

    canvasWrapper.drawPicture(svgPicture);
    svgCanvas.translate(-xOffset, -yOffset);

    //surya


    /// draw the texts one by one in below of each other
    var topPosSeek = tooltipData.tooltipPadding.top;
    for (var tp in drawingTextPainters) {
      double yOffset = rect.topCenter.dy +
          topPosSeek -
          textRotationOffset.dy +
          rectRotationOffset.dy;

      double xOffset;
      switch (tp.textAlign.getFinalHorizontalAlignment(tp.textDirection)) {
        case HorizontalAlignment.left:
          xOffset = rect.left + tooltipData.tooltipPadding.left;
          break;
        case HorizontalAlignment.right:
          xOffset = rect.right - tooltipData.tooltipPadding.right - tp.width;
          break;
        default:
          xOffset = rect.center.dx - (tp.width / 2);
          break;
      }

      final ui.Offset drawOffset = Offset(
        xOffset,
        yOffset,
      );

      // canvasWrapper.drawRotated(
      //   size: rect.size,
      //   rotationOffset: rectRotationOffset,
      //   drawOffset: rectDrawOffset,
      //   angle: rotateAngle,
      //   drawCallback: () {
      //     canvasWrapper.drawText(tp, drawOffset);
      //   },
      // );
      topPosSeek += tp.height;
      topPosSeek += textsBelowMargin;
    }
  }

  @visibleForTesting
  double getBarLineXLength(
    LineChartBarData barData,
    Size chartUsableSize,
    PaintHolder<LineChartData> holder,
  ) {
    if (barData.spots.isEmpty) {
      return 0.0;
    }

    final firstSpot = barData.spots[0];
    final firstSpotX = getPixelX(firstSpot.x, chartUsableSize, holder);

    final lastSpot = barData.spots[barData.spots.length - 1];
    final lastSpotX = getPixelX(lastSpot.x, chartUsableSize, holder);

    return lastSpotX - firstSpotX;
  }

  /// Makes a [LineTouchResponse] based on the provided [localPosition]
  ///
  /// Processes [localPosition] and checks
  /// the elements of the chart that are near the offset,
  /// then makes a [LineTouchResponse] from the elements that has been touched.
  List<TouchLineBarSpot>? handleTouch(
    Offset localPosition,
    Size size,
    PaintHolder<LineChartData> holder,
  ) {
    final data = holder.data;

    /// it holds list of nearest touched spots of each line
    /// and we use it to draw touch stuff on them
    final touchedSpots = <TouchLineBarSpot>[];

    /// draw each line independently on the chart
    for (var i = 0; i < data.lineBarsData.length; i++) {
      final barData = data.lineBarsData[i];

      // find the nearest spot on touch area in this bar line
      final foundTouchedSpot =
          getNearestTouchedSpot(size, localPosition, barData, i, holder);
      if (foundTouchedSpot != null) {
        touchedSpots.add(foundTouchedSpot);
      }
    }

    touchedSpots.sort((a, b) => a.distance.compareTo(b.distance));

    return touchedSpots.isEmpty ? null : touchedSpots;
  }

  /// find the nearest spot base on the touched offset
  @visibleForTesting
  TouchLineBarSpot? getNearestTouchedSpot(
    Size viewSize,
    Offset touchedPoint,
    LineChartBarData barData,
    int barDataPosition,
    PaintHolder<LineChartData> holder,
  ) {
    final data = holder.data;
    if (!barData.show) {
      return null;
    }

    /// Find the nearest spot (based on distanceCalculator)
    final sortedSpots = <FlSpot>[];
    double? smallestDistance;
    for (var spot in barData.spots) {
      if (spot.isNull()) continue;
      final distance = data.lineTouchData.distanceCalculator(
          touchedPoint,
          Offset(
            getPixelX(spot.x, viewSize, holder),
            getPixelY(spot.y, viewSize, holder),
          ));

      if (distance <= data.lineTouchData.touchSpotThreshold) {
        smallestDistance ??= distance;

        if (distance < smallestDistance) {
          sortedSpots.insert(0, spot);
          smallestDistance = distance;
        } else {
          sortedSpots.add(spot);
        }
      }
    }

    if (sortedSpots.isNotEmpty) {
      return TouchLineBarSpot(
          barData, barDataPosition, sortedSpots.first, smallestDistance!);
    } else {
      return null;
    }
  }
}

@visibleForTesting
class LineIndexDrawingInfo {
  final LineChartBarData line;
  final int lineIndex;
  final FlSpot spot;
  final int spotIndex;
  final TouchedSpotIndicatorData indicatorData;

  LineIndexDrawingInfo(
    this.line,
    this.lineIndex,
    this.spot,
    this.spotIndex,
    this.indicatorData,
  );
}
