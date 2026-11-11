import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

// ✅ Les enums sont ici
enum MetricType { puissance, tension, courant, status }
enum PeriodType { day, month, year, total, custom }

class DashboardChart extends StatelessWidget {
  final List<FlSpot> spotsConso;
  final List<FlSpot> spotsProd;
  final List<Map<String, dynamic>> barData;
  final MetricType selectedMetric;
  final PeriodType selectedPeriod;
  final DateTime customStart;
  final DateTime customEnd;
  final DateTime? tempStartSelection;
  final DateTime selectedDate;
  final int hourRange;
  final bool isDark;
  final Function(FlTouchEvent, LineTouchResponse?) onGraphTouch;

  const DashboardChart({
    super.key,
    required this.spotsConso,
    required this.spotsProd,
    required this.barData,
    required this.selectedMetric,
    required this.selectedPeriod,
    required this.customStart,
    required this.customEnd,
    required this.tempStartSelection,
    required this.selectedDate,
    required this.hourRange,
    required this.isDark,
    required this.onGraphTouch,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedPeriod == PeriodType.day || selectedPeriod == PeriodType.custom) {
      return _buildLineChart(context);
    } else {
      return _buildBarChart(context);
    }
  }

  Widget _buildLineChart(BuildContext context) {
    bool isStatusGraph = selectedMetric == MetricType.status;
    
    double maxY = 10;
    if (!isStatusGraph) {
      if (spotsConso.isNotEmpty) maxY = spotsConso.map((e) => e.y).reduce(max);
      if (spotsProd.isNotEmpty) maxY = max(maxY, spotsProd.map((e) => e.y).reduce(max));
      maxY = maxY <= 0 ? 10 : maxY * 1.2;
    } else maxY = 1.2;
    
    final gridColor = isDark ? Colors.white12 : Colors.grey.shade300;
    
    double minX = 0;
    double maxX = 24;
    
    if (selectedPeriod == PeriodType.custom) {
      if (spotsConso.isNotEmpty) {
        minX = spotsConso.map((e) => e.x).reduce(min) - 1;
        maxX = spotsConso.map((e) => e.x).reduce(max) + 1;
      } else {
        minX = customStart.millisecondsSinceEpoch / 3600000.0;
        maxX = customEnd.millisecondsSinceEpoch / 3600000.0;
      }
      if (maxX <= minX) maxX = minX + 1;
    } else {
      DateTime startTime = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 0, 0, 0);
      if (hourRange < 24) {
        startTime = DateTime.now().subtract(Duration(hours: hourRange));
      }
      minX = hourRange == 24 ? 0 : startTime.hour + (startTime.minute / 60.0);
      maxX = hourRange == 24 ? 24 : minX + hourRange;
      if (maxX > 24) maxX = 24; 
    }

    double xInterval = (maxX - minX) / 6;
    if (xInterval <= 0) xInterval = 0.1;

    Color chartColor = _getChartColor();
    String chartUnit = _getChartUnit();

    return Listener(
      onPointerSignal: (event) { if (event is PointerScrollEvent) GestureBinding.instance.pointerSignalResolver.register(event, (event) {}); },
      child: LineChart(
        LineChartData(
          minX: minX, maxX: maxX, minY: isStatusGraph ? -0.2 : 0, maxY: maxY,
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: isStatusGraph ? 1 : maxY / 5, getDrawingHorizontalLine: (value) => FlLine(color: gridColor, strokeWidth: 1, dashArray: [5, 5])),
          
          extraLinesData: ExtraLinesData(
            verticalLines: [
              if (selectedPeriod == PeriodType.custom) ...[
                VerticalLine(
                  x: customStart.millisecondsSinceEpoch / 3600000.0,
                  color: Colors.green, strokeWidth: 2, dashArray: [4, 4],
                  label: VerticalLineLabel(show: true, labelResolver: (line) => 'Début', style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold), alignment: Alignment.topRight),
                ),
                VerticalLine(
                  x: customEnd.millisecondsSinceEpoch / 3600000.0,
                  color: Colors.red, strokeWidth: 2, dashArray: [4, 4],
                  label: VerticalLineLabel(show: true, labelResolver: (line) => 'Fin', style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold), alignment: Alignment.topLeft),
                ),
                if (tempStartSelection != null)
                  VerticalLine(
                    x: tempStartSelection!.millisecondsSinceEpoch / 3600000.0,
                    color: Colors.orange, strokeWidth: 2, dashArray: [2, 2],
                    label: VerticalLineLabel(show: true, labelResolver: (line) => 'En attente...', style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold), alignment: Alignment.topLeft),
                  ),
              ]
            ],
          ),

          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: isStatusGraph ? 65 : 35, interval: isStatusGraph ? 1 : maxY / 5, getTitlesWidget: (value, meta) {
              if (isStatusGraph) {
                if (value == 1) return const Text('En ligne', style: TextStyle(color: Colors.green, fontSize: 11));
                if (value == 0) return const Text('Hors ligne', style: TextStyle(color: Colors.red, fontSize: 11));
                return const SizedBox.shrink();
              }
              return Text(value.toStringAsFixed(1), style: const TextStyle(color: Colors.grey, fontSize: 11));
            })),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: xInterval, getTitlesWidget: (value, meta) {
              if (value < minX || value > maxX) return const SizedBox.shrink();
              
              DateTime tickTime;
              if (selectedPeriod == PeriodType.custom) {
                tickTime = DateTime.fromMillisecondsSinceEpoch((value * 3600000).toInt());
                if ((maxX - minX) < 24) {
                  return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(DateFormat('HH:mm').format(tickTime), style: const TextStyle(color: Colors.grey, fontSize: 11)));
                } else {
                  return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(DateFormat('dd/MM HH:mm').format(tickTime), style: const TextStyle(color: Colors.grey, fontSize: 10)));
                }
              } else {
                if (hourRange == 24) {
                  tickTime = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, value.toInt(), 0);
                } else {
                  tickTime = DateTime.now().subtract(Duration(hours: hourRange)).add(Duration(minutes: (value * 60).toInt()));
                }
                return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(DateFormat('HH:mm').format(tickTime), style: const TextStyle(color: Colors.grey, fontSize: 11)));
              }
            })),
          ),
          borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: gridColor, width: 1), left: BorderSide(color: gridColor, width: 1))),
          
          lineTouchData: LineTouchData(
            touchCallback: onGraphTouch, 
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (spot) => const Color(0xFF2C313C), tooltipBorder: const BorderSide(color: Colors.white24), tooltipPadding: const EdgeInsets.all(8),
              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                return touchedSpots.map((spot) {
                  if (spot.y == 0 && !isStatusGraph) return null; 
                  
                  DateTime spotTime;
                  if (selectedPeriod == PeriodType.custom) {
                    spotTime = DateTime.fromMillisecondsSinceEpoch((spot.x * 3600000).toInt());
                  } else {
                    if (hourRange == 24) {
                      spotTime = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, spot.x.toInt(), ((spot.x % 1) * 60).toInt());
                    } else {
                      spotTime = DateTime.now().subtract(Duration(hours: hourRange)).add(Duration(minutes: (spot.x * 60).toInt()));
                    }
                  }

                  String timeStr = selectedPeriod == PeriodType.custom && (maxX - minX) > 24
                      ? DateFormat('dd/MM HH:mm').format(spotTime)
                      : DateFormat('HH:mm').format(spotTime);
                      
                  String label = isStatusGraph ? (spot.y == 1 ? 'En ligne' : 'Hors ligne') : '${spot.y.toStringAsFixed(1)} $chartUnit';
                  Color textColor = isStatusGraph ? (spot.y == 1 ? Colors.green : Colors.red) : chartColor;

                  return LineTooltipItem(
                    '$timeStr\n',
                    const TextStyle(color: Colors.white, fontSize: 11),
                    children: [TextSpan(text: label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13))],
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spotsConso, isCurved: false, isStepLineChart: isStatusGraph,
              lineChartStepData: LineChartStepData(stepDirection: LineChartStepData.stepDirectionForward),
              color: isStatusGraph ? Colors.green : const Color(0xFFF5B041), 
              barWidth: isStatusGraph ? 2 : 2, dotData: const FlDotData(show: false), 
              belowBarData: BarAreaData(show: true, color: isStatusGraph ? Colors.green.withOpacity(0.1) : const Color(0xFFF5B041).withOpacity(0.3)),
            ),
            if (selectedMetric == MetricType.puissance)
              LineChartBarData(
                spots: spotsProd, isCurved: false, color: const Color(0xFF1ABC9C), 
                barWidth: 2, dotData: const FlDotData(show: false), 
                belowBarData: BarAreaData(show: true, color: const Color(0xFF1ABC9C).withOpacity(0.3)),
              ),
          ],
        ),
        transformationConfig: const FlTransformationConfig(scaleAxis: FlScaleAxis.horizontal, minScale: 1.0, maxScale: 20.0, panEnabled: true),
      ),
    );
  }

  Widget _buildBarChart(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (barData.isEmpty) return const SizedBox.shrink();

        int numBars = barData.length;
        double finalBarWidth = ((constraints.maxWidth - 60) / numBars * 0.3).clamp(3.0, 12.0);

        double maxVal = 0;
        for (var item in barData) maxVal = max(maxVal, max(item['conso'], item['prod']));
        if (maxVal == 0) maxVal = 1;
        
        double interval = maxVal < 1 ? 0.2 : maxVal / 5;
        if (interval <= 0) interval = 0.1;
        
        double maxY = (maxVal / interval).ceil() * interval;
        final gridColor = isDark ? Colors.white12 : Colors.grey.shade300;

        List<BarChartGroupData> groups = barData.map((item) {
          return BarChartGroupData(
            x: item['x'],
            barRods: [
              BarChartRodData(toY: item['conso'], color: const Color(0xFFF5B041), width: finalBarWidth, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
              BarChartRodData(toY: item['prod'], color: const Color(0xFF1ABC9C), width: finalBarWidth, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
            ],
          );
        }).toList();

        return BarChart(
          BarChartData(
            maxY: maxY, barGroups: groups, alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: interval, getDrawingHorizontalLine: (value) => FlLine(color: gridColor, strokeWidth: 1, dashArray: [5, 5])),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, interval: interval, getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(1), style: const TextStyle(color: Colors.grey, fontSize: 11)))),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) {
                if (value < 1 || value > 31) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(value.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 10)));
              })),
            ),
            borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: gridColor, width: 1), left: BorderSide(color: gridColor, width: 1))),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (group) => const Color(0xFF2C313C), tooltipBorder: const BorderSide(color: Colors.white24), tooltipPadding: const EdgeInsets.all(8),
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  if (rod.toY == 0) return null; 
                  String type = rodIndex == 0 ? "Conso" : "Prod";
                  Color c = rodIndex == 0 ? const Color(0xFFF5B041) : const Color(0xFF1ABC9C);
                  return BarTooltipItem('Le ${group.x} : $type\n', const TextStyle(color: Colors.white, fontSize: 11), children: [TextSpan(text: '${rod.toY.toStringAsFixed(3)} kWh', style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 13))]);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getChartColor() {
    if (selectedPeriod != PeriodType.day) return const Color(0xFFF5B041);
    switch (selectedMetric) {
      case MetricType.puissance: return const Color(0xFFF5B041);
      case MetricType.tension: return const Color(0xFF3498DB);
      case MetricType.courant: return const Color(0xFFE74C3C);
      case MetricType.status: return Colors.green;
    }
  }

  String _getChartUnit() {
    switch (selectedMetric) {
      case MetricType.puissance: return 'W';
      case MetricType.tension: return 'V';
      case MetricType.courant: return 'A';
      case MetricType.status: return '';
    }
  }
}