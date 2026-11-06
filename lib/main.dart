import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  try {
    await FirebaseAuth.instance.signInAnonymously();
  } catch (e) {
    debugPrint("Erreur Auth: $e");
  }

  runApp(const SmartMeterApp());
}

class SmartMeterApp extends StatefulWidget {
  const SmartMeterApp({super.key});

  @override
  State<SmartMeterApp> createState() => _SmartMeterAppState();
}

class _SmartMeterAppState extends State<SmartMeterApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Meter Pro',
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
        primaryColor: const Color(0xFFE67E22),
        cardColor: Colors.white,
        dividerColor: Colors.grey.shade300,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        primaryColor: const Color(0xFFE67E22),
        cardColor: const Color(0xFF1A1D24),
        dividerColor: Colors.white12,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: DashboardScreen(
        isDarkMode: _themeMode == ThemeMode.dark,
        onToggleTheme: _toggleTheme,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

enum MetricType { puissance, tension, courant, status }
enum PeriodType { day, month, year, total }

class DashboardScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const DashboardScreen({super.key, required this.isDarkMode, required this.onToggleTheme});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseReference _realtimeRef = FirebaseDatabase.instance.ref('compteur/temps_reel');
  final DatabaseReference _historyRef = FirebaseDatabase.instance.ref('historique/live');
  
  StreamSubscription<DatabaseEvent>? _rtSubscription;
  StreamSubscription<DatabaseEvent>? _historySubscription;

  double _tension = 0.0;
  double _courant = 0.0;
  double _puissance = 0.0;
  double _energieTotale = 0.0;
  int _offlinePending = 0;
  
  DateTime? _lastSeenTime;
  final Duration _offlineThreshold = const Duration(minutes: 2);
  
  final double _alertThreshold = 2000.0;

  double _energieBaseReset = -1.0;
  double _energieBaseJournaliere = -1.0;
  int _lastDay = -1;

  int _hourRange = 24; 
  
  MetricType _selectedMetric = MetricType.puissance;
  PeriodType _selectedPeriod = PeriodType.day;
  DateTime _selectedDate = DateTime.now();

  final List<Map<String, dynamic>> _historyData = [];

  @override
  void initState() {
    super.initState();
    _setupFirebaseListeners();
  }

  bool get _isEspOnline {
    if (_lastSeenTime == null) return false;
    return DateTime.now().difference(_lastSeenTime!) < _offlineThreshold;
  }

  void _setupFirebaseListeners() {
    _rtSubscription = _realtimeRef.onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        setState(() {
          _tension = (data['tension'] ?? 0).toDouble();
          _courant = (data['courant'] ?? 0).toDouble();
          _puissance = (data['puissance'] ?? 0).toDouble();
          _energieTotale = (data['energie_totale'] ?? 0).toDouble();
          _offlinePending = (data['offline_pending'] ?? 0).toInt();

          if (data['timestamp'] != null) {
            _lastSeenTime = DateTime.fromMillisecondsSinceEpoch((data['timestamp'] as int) * 1000);
          } else {
            _lastSeenTime = DateTime.now();
          }

          DateTime now = DateTime.now();
          if (_energieBaseReset == -1.0) _energieBaseReset = _energieTotale;
          if (_lastDay == -1) {
            _lastDay = now.day;
            _energieBaseJournaliere = _energieTotale;
          } else if (now.day != _lastDay) {
            _lastDay = now.day;
            _energieBaseJournaliere = _energieTotale;
          }
        });
      }
    });

    _loadHistory();
  }

  void _loadHistory() {
    _historySubscription = _historyRef.onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        List<Map<String, dynamic>> loadedData = [];
        data.forEach((key, value) {
          final map = value as Map<dynamic, dynamic>;
          DateTime date = DateTime.fromMillisecondsSinceEpoch((map['timestamp'] ?? 0) * 1000);
          loadedData.add({
            'time': date,
            'v': (map['tension'] ?? 0).toDouble(),
            'i': (map['courant'] ?? 0).toDouble(),
            'p': (map['puissance'] ?? 0).toDouble(),
          });
        });
        loadedData.sort((a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));
        setState(() {
          _historyData.clear();
          _historyData.addAll(loadedData);
        });
      }
    });
  }

  void _resetData() {
    setState(() {
      _energieBaseReset = _energieTotale;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Compteur (Reset) remis à zéro !'), backgroundColor: Colors.green),
    );
  }

  void _changeDate(int increment) {
    setState(() {
      if (_selectedPeriod == PeriodType.day) {
        _selectedDate = _selectedDate.add(Duration(days: increment));
        if (_selectedDate.day != DateTime.now().day || _selectedDate.month != DateTime.now().month || _selectedDate.year != DateTime.now().year) {
          _hourRange = 24; 
        }
      } else if (_selectedPeriod == PeriodType.month) {
        _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + increment, 1);
      } else if (_selectedPeriod == PeriodType.year) {
        _selectedDate = DateTime(_selectedDate.year + increment, 1, 1);
      }
    });
  }

  void _exportToCSV() {
    if (_historyData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune donnée à exporter.')));
      return;
    }

    String csvData = "Date;Heure;Tension (V);Courant (A);Puissance (W)\n";

    var filteredData = _historyData.where((data) {
      DateTime time = data['time'];
      if (_selectedPeriod == PeriodType.day) {
        return time.year == _selectedDate.year && time.month == _selectedDate.month && time.day == _selectedDate.day;
      } else if (_selectedPeriod == PeriodType.month) {
        return time.year == _selectedDate.year && time.month == _selectedDate.month;
      } else if (_selectedPeriod == PeriodType.year) {
        return time.year == _selectedDate.year;
      }
      return true;
    });

    for (var row in filteredData) {
      DateTime dt = row['time'];
      csvData += "${DateFormat('yyyy-MM-dd').format(dt)};${DateFormat('HH:mm:ss').format(dt)};${row['v'].toStringAsFixed(1)};${row['i'].toStringAsFixed(2)};${row['p'].toStringAsFixed(1)}\n";
    }

    final bytes = utf8.encode(csvData);
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..style.display = 'none'
      ..download = 'export_smartmeter_${DateFormat('yyyyMMdd').format(_selectedDate)}.csv';
    
    html.document.body!.children.add(anchor);
    anchor.click();
    html.document.body!.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Export CSV téléchargé !'), backgroundColor: Colors.green));
  }

  @override
  void dispose() {
    _rtSubscription?.cancel();
    _historySubscription?.cancel();
    super.dispose();
  }

  double get _energieDepuisReset => (_energieTotale - _energieBaseReset).clamp(0.0, double.infinity);
  double get _energieJournaliere => (_energieTotale - _energieBaseJournaliere).clamp(0.0, double.infinity);

  Color get _chartColor {
    if (_selectedPeriod != PeriodType.day) return const Color(0xFFF5B041);
    switch (_selectedMetric) {
      case MetricType.puissance: return const Color(0xFFF5B041);
      case MetricType.tension: return const Color(0xFF3498DB);
      case MetricType.courant: return const Color(0xFFE74C3C);
      case MetricType.status: return Colors.green;
    }
  }

  String get _chartUnit {
    switch (_selectedMetric) {
      case MetricType.puissance: return 'W';
      case MetricType.tension: return 'V';
      case MetricType.courant: return 'A';
      case MetricType.status: return '';
    }
  }
  
  String get _chartLabel {
    if (_selectedPeriod != PeriodType.day) return 'Énergie (kWh)';
    switch (_selectedMetric) {
      case MetricType.puissance: return 'Consommation';
      case MetricType.tension: return 'Tension';
      case MetricType.courant: return 'Courant';
      case MetricType.status: return 'Connexion ESP';
    }
  }

  List<FlSpot> get _chartSpots {
    if (_historyData.isEmpty) return [];

    DateTime now = DateTime.now();
    DateTime startTime = now.subtract(Duration(hours: _hourRange));
    bool isToday = _selectedDate.day == now.day && _selectedDate.month == now.month && _selectedDate.year == now.year;

    var filtered = _historyData.where((data) {
      DateTime date = data['time'];
      bool isSameDay = date.year == _selectedDate.year && date.month == _selectedDate.month && date.day == _selectedDate.day;
      if (isSameDay && isToday) return date.isAfter(startTime);
      return isSameDay;
    }).toList();

    if (_selectedMetric == MetricType.status) {
      List<FlSpot> statusSpots = [];
      DateTime? prevTime;
      
      for (var data in filtered) {
        DateTime currTime = data['time'];
        double xVal = isToday ? currTime.difference(startTime).inMinutes / 60.0 : currTime.hour + (currTime.minute / 60.0);
        
        if (prevTime != null) {
          if (currTime.difference(prevTime).inMinutes > 2) {
             double xOffline = isToday ? prevTime.difference(startTime).inMinutes / 60.0 : prevTime.hour + (prevTime.minute / 60.0);
             statusSpots.add(FlSpot(xOffline + 0.01, 0)); 
             statusSpots.add(FlSpot(xVal, 0)); 
          }
        }
        
        statusSpots.add(FlSpot(xVal, 1));
        prevTime = currTime;
      }
      return statusSpots;
    } else {
      return filtered.map((data) {
        final time = data['time'] as DateTime;
        double xValue = isToday ? time.difference(startTime).inMinutes / 60.0 : time.hour + (time.minute / 60.0);
        double yValue = 0.0;
        if (_selectedMetric == MetricType.puissance) yValue = data['p'];
        if (_selectedMetric == MetricType.tension) yValue = data['v'];
        if (_selectedMetric == MetricType.courant) yValue = data['i'];
        return FlSpot(xValue, yValue);
      }).toList();
    }
  }

  List<Map<String, dynamic>> _getBarData() {
    if (_historyData.isEmpty) return [];
    Map<int, double> aggregatedEnergyKwh = {};

    var filteredData = _historyData.where((data) {
      DateTime time = data['time'];
      if (_selectedPeriod == PeriodType.month) {
        return time.year == _selectedDate.year && time.month == _selectedDate.month;
      } else if (_selectedPeriod == PeriodType.year) {
        return time.year == _selectedDate.year;
      }
      return true;
    });

    for (var data in filteredData) {
      DateTime time = data['time'];
      double p = data['p']; 
      int key = 0;
      if (_selectedPeriod == PeriodType.month) key = time.day;
      else if (_selectedPeriod == PeriodType.year) key = time.month;
      else if (_selectedPeriod == PeriodType.total) key = time.year;

      double energyKwh = p * (1.0 / 60.0) / 1000.0;
      aggregatedEnergyKwh[key] = (aggregatedEnergyKwh[key] ?? 0.0) + energyKwh;
    }

    List<Map<String, dynamic>> groups = [];
    int startX = 1;
    int endX = 31;
    if (_selectedPeriod == PeriodType.year) endX = 12;
    else if (_selectedPeriod == PeriodType.total) {
      int minYear = 9999;
      int maxYear = 0;
      aggregatedEnergyKwh.forEach((key, value) {
        if (key < minYear) minYear = key;
        if (key > maxYear) maxYear = key;
      });
      startX = minYear == 9999 ? DateTime.now().year : minYear;
      endX = maxYear == 0 ? DateTime.now().year : maxYear;
    }

    for (int i = startX; i <= endX; i++) {
      double val = aggregatedEnergyKwh[i] ?? 0.0;
      groups.add({'x': i, 'y': val});
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    bool isAlert = _puissance > _alertThreshold;
    bool isOnline = _isEspOnline;
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/logo.png', height: 32, fit: BoxFit.contain),
            const SizedBox(width: 12),
            Text('Smart Meter', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: textColor)),
            const SizedBox(width: 12),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: (isOnline ? Colors.green : Colors.red).withOpacity(0.5), blurRadius: 6, spreadRadius: 2)
                ]
              ),
            ),
            if (_offlinePending > 0) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange)),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, size: 14, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text('$_offlinePending', style: const TextStyle(fontSize: 11, color: Colors.orange)),
                  ],
                ),
              )
            ]
          ],
        ),
        backgroundColor: cardColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: Colors.orange),
            tooltip: 'Changer de thème',
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFFE67E22)),
            tooltip: 'Reset',
            onPressed: _resetData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (!isOnline)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  border: Border.all(color: Colors.red.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _lastSeenTime == null 
                          ? "ESP jamais connecté" 
                          : "ESP Hors ligne. Dernière connexion : ${DateFormat('dd/MM à HH:mm').format(_lastSeenTime!)}",
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

            LayoutBuilder(
              builder: (context, constraints) {
                bool isMobile = constraints.maxWidth < 700;
                
                Widget gaugeWidget = Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isAlert ? Colors.red : borderColor, width: isAlert ? 2 : 1),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    children: [
                      Text('Puissance Actuelle', style: TextStyle(color: Colors.grey, fontSize: 14)),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 120,
                        width: 220,
                        child: CustomPaint(
                          painter: GaugePainter(
                            value: _puissance,
                            maxValue: _alertThreshold * 1.5,
                            alertThreshold: _alertThreshold,
                            bgColor: borderColor,
                            needleColor: textColor,
                          ),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${_puissance.toStringAsFixed(0)} W',
                                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: isAlert ? Colors.red : const Color(0xFFE67E22)),
                                  ),
                                  if (isAlert) const Text('ALERTE !', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                Widget metricsWidget = Column(
                  children: [
                    _buildMetricCard('Énergie (Reset)', '${_energieDepuisReset.toStringAsFixed(3)} kWh', Icons.restart_alt, const Color(0xFF3498DB)),
                    const SizedBox(height: 12),
                    _buildMetricCard('Énergie Journalière', '${_energieJournaliere.toStringAsFixed(3)} kWh', Icons.today, const Color(0xFF2ECC71)),
                    const SizedBox(height: 12),
                    _buildMetricCard('Énergie Totale', '${_energieTotale.toStringAsFixed(3)} kWh', Icons.electric_meter, const Color(0xFFE67E22)),
                  ],
                );

                if (isMobile) {
                  return Column(
                    children: [
                      gaugeWidget,
                      const SizedBox(height: 16), 
                      metricsWidget
                    ],
                  );
                } else {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 1, child: Center(child: gaugeWidget)),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: Row(
                        children: [
                          Expanded(child: _buildMetricCard('Énergie (Reset)', '${_energieDepuisReset.toStringAsFixed(3)} kWh', Icons.restart_alt, const Color(0xFF3498DB))),
                          const SizedBox(width: 16),
                          Expanded(child: _buildMetricCard('Énergie Journalière', '${_energieJournaliere.toStringAsFixed(3)} kWh', Icons.today, const Color(0xFF2ECC71))),
                          const SizedBox(width: 16),
                          Expanded(child: _buildMetricCard('Énergie Totale', '${_energieTotale.toStringAsFixed(3)} kWh', Icons.electric_meter, const Color(0xFFE67E22))),
                        ],
                      )),
                    ],
                  );
                }
              },
            ),
            
            const SizedBox(height: 16),

            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopControls(isDark, borderColor),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: _chartColor)),
                      const SizedBox(width: 8),
                      Text(_chartLabel, style: TextStyle(color: Colors.grey, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 300,
                    child: _historyData.isEmpty 
                        ? const Center(child: Text('Aucune donnée disponible...', style: TextStyle(color: Colors.grey)))
                        : (_selectedPeriod == PeriodType.day ? _buildLineChart(isDark) : _buildBarChart(isDark)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopControls(bool isDark, Color borderColor) {
    String dateText = "";
    if (_selectedPeriod == PeriodType.day) {
      dateText = DateFormat('yyyy-MM-dd').format(_selectedDate);
    } else if (_selectedPeriod == PeriodType.month) {
      dateText = DateFormat('yyyy-MM').format(_selectedDate);
    } else if (_selectedPeriod == PeriodType.year) {
      dateText = DateFormat('yyyy').format(_selectedDate);
    } else {
      dateText = "Tout";
    }
    
    final textColor = isDark ? Colors.white : Colors.black87;
    
    Widget tabsWidget = Container(
      decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabButton('Day', PeriodType.day),
          _buildTabButton('Month', PeriodType.month),
          _buildTabButton('Year', PeriodType.year),
          _buildTabButton('Total', PeriodType.total),
        ],
      ),
    );

    Widget dateWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_selectedPeriod != PeriodType.total) ...[
          IconButton(icon: const Icon(Icons.chevron_left, color: Colors.grey, size: 20), onPressed: () => _changeDate(-1), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ],
        const SizedBox(width: 8),
        Text(dateText, style: TextStyle(fontSize: 14, color: textColor, fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        if (_selectedPeriod != PeriodType.total) ...[
          IconButton(icon: const Icon(Icons.chevron_right, color: Colors.grey, size: 20), onPressed: () => _changeDate(1), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ],
      ],
    );

    Widget actionsWidget = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        if (_selectedPeriod == PeriodType.day)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _hourRange,
                dropdownColor: Theme.of(context).cardColor,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                style: TextStyle(color: textColor, fontSize: 13),
                onChanged: (val) { if (val != null) setState(() => _hourRange = val); },
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 Heure')),
                  DropdownMenuItem(value: 6, child: Text('6 Heures')),
                  DropdownMenuItem(value: 12, child: Text('12 Heures')),
                  DropdownMenuItem(value: 24, child: Text('24 Heures')),
                ],
              ),
            ),
          ),
        
        if (_selectedPeriod == PeriodType.day)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<MetricType>(
                value: _selectedMetric,
                dropdownColor: Theme.of(context).cardColor,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                style: TextStyle(color: textColor, fontSize: 13),
                onChanged: (val) { if (val != null) setState(() => _selectedMetric = val); },
                items: const [
                  DropdownMenuItem(value: MetricType.puissance, child: Text('Puissance (W)')),
                  DropdownMenuItem(value: MetricType.tension, child: Text('Tension (V)')),
                  DropdownMenuItem(value: MetricType.courant, child: Text('Courant (A)')),
                  DropdownMenuItem(value: MetricType.status, child: Text('Statut ESP (Connexion)')), 
                ],
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey.shade200, border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)),
            child: Text('Énergie (kWh)', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          
        OutlinedButton.icon(
          onPressed: _exportToCSV,
          icon: const Icon(Icons.download, size: 16, color: Colors.grey),
          label: const Text('Export', style: TextStyle(color: Colors.grey, fontSize: 13)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            side: BorderSide(color: borderColor), 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))
          ),
        )
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Column(
            children: [
              Center(child: tabsWidget),
              const SizedBox(height: 12),
              Center(child: dateWidget),
              const SizedBox(height: 12),
              Center(child: actionsWidget),
            ],
          );
        } else {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              tabsWidget,
              dateWidget,
              actionsWidget,
            ],
          );
        }
      }
    );
  }

  Widget _buildTabButton(String text, PeriodType period) {
    bool isActive = _selectedPeriod == period;
    return GestureDetector(
      onTap: () => setState(() => _selectedPeriod = period),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE67E22) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.grey,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildLineChart(bool isDark) {
    final spots = _chartSpots;
    bool isStatusGraph = _selectedMetric == MetricType.status;
    
    double maxY;
    double minY;
    
    if (isStatusGraph) {
      maxY = 1.2; 
      minY = -0.2; 
    } else {
      maxY = spots.isEmpty ? 10 : spots.map((e) => e.y).reduce((a, b) => a > b ? a : b); 
      if (maxY <= 0 || maxY.isNaN) maxY = 10; 
      
      // Calcul de l'échelle Y logique
      if (maxY <= 0.1) maxY = 0.1;
      else if (maxY <= 0.5) maxY = 0.5;
      else if (maxY <= 1) maxY = 1;
      else if (maxY <= 5) maxY = 5;
      else if (maxY <= 10) maxY = 10;
      else if (maxY <= 50) maxY = 50;
      else if (maxY <= 100) maxY = 100;
      else maxY = maxY.ceilToDouble();

      maxY = maxY * 1.2; 
      minY = 0;
    }
    
    final gridColor = isDark ? Colors.white12 : Colors.grey.shade300;
    
    DateTime now = DateTime.now();
    DateTime startTime = now.subtract(Duration(hours: _hourRange));
    bool isToday = _selectedDate.day == now.day && _selectedDate.month == now.month;

    double interval = _hourRange.toDouble() / 6;

    return LineChart(
      LineChartData(
        minX: 0, maxX: isToday ? _hourRange.toDouble() : 24, minY: minY, maxY: maxY,
        gridData: FlGridData(
          show: true, 
          drawVerticalLine: false, 
          horizontalInterval: isStatusGraph ? 1 : maxY / 5,
          getDrawingHorizontalLine: (value) => FlLine(color: gridColor, strokeWidth: 1, dashArray: [5, 5])
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, 
              reservedSize: isStatusGraph ? 65 : 35, 
              interval: isStatusGraph ? 1 : maxY / 5,
              getTitlesWidget: (value, meta) {
                if (isStatusGraph) {
                  if (value == 1) return const Text('En ligne', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold));
                  if (value == 0) return const Text('Hors ligne', style: TextStyle(color: Colors.red, fontSize: 11));
                  return const SizedBox.shrink();
                }
                return Text(value.toStringAsFixed(1), style: const TextStyle(color: Colors.grey, fontSize: 11));
              }
            )
          ),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: isToday ? interval : 4,
            getTitlesWidget: (value, meta) {
              if (value < 0 || value > (isToday ? _hourRange : 24)) return const SizedBox.shrink();
              
              DateTime tickTime;
              if (isToday) {
                tickTime = startTime.add(Duration(minutes: (value * 60).toInt()));
              } else {
                tickTime = DateTime(now.year, now.month, now.day, value.toInt());
              }
              
              return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(DateFormat('HH:mm').format(tickTime), style: const TextStyle(color: Colors.grey, fontSize: 11)));
            })),
        ),
        borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: gridColor, width: 1), left: BorderSide(color: gridColor, width: 1))),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) => Theme.of(context).cardColor, tooltipBorder: BorderSide(color: gridColor), tooltipPadding: const EdgeInsets.all(8),
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((spot) {
                DateTime spotTime;
                if (isToday) {
                  spotTime = startTime.add(Duration(minutes: (spot.x * 60).toInt()));
                } else {
                  spotTime = DateTime(now.year, now.month, now.day, spot.x.toInt(), ((spot.x % 1) * 60).toInt());
                }

                if (isStatusGraph) {
                  return LineTooltipItem(
                    '${DateFormat('HH:mm').format(spotTime)}\n',
                    const TextStyle(color: Colors.grey, fontSize: 11),
                    children: [
                      TextSpan(
                        text: spot.y == 1 ? 'En ligne' : 'Hors ligne', 
                        style: TextStyle(color: spot.y == 1 ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12)
                      )
                    ],
                  );
                }
                
                return LineTooltipItem(
                  '${DateFormat('HH:mm').format(spotTime)}\n',
                  const TextStyle(color: Colors.grey, fontSize: 11),
                  children: [TextSpan(text: '${spot.y.toStringAsFixed(1)} $_chartUnit', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 12))],
                );
              }).toList();
            },
          ),
        ),
                lineBarsData: [
          LineChartBarData(
            spots: spots, 
            isCurved: false, 
            isStepLineChart: isStatusGraph,
            // ✅ CORRECTION ICI : Utilisation de la constante correcte
            lineChartStepData: LineChartStepData(stepDirection: LineChartStepData.stepDirectionForward),
            color: isStatusGraph ? Colors.green : Colors.transparent, 
            barWidth: isStatusGraph ? 2 : 0, 
            dotData: const FlDotData(show: false), 
            belowBarData: BarAreaData(show: true, color: isStatusGraph ? Colors.green.withOpacity(0.1) : _chartColor.withOpacity(0.4)),
          ),
        ],
      ),
    );
  }

  // ✅ CORRECTION DE LA LARGEUR DES BARRES ET DE L'AXE Y
  Widget _buildBarChart(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rawBarData = _getBarData();
        if (rawBarData.isEmpty) return const SizedBox.shrink();

        int numBars = rawBarData.length;
        // Calcul de la place disponible
        double availableWidth = constraints.maxWidth - 60; 
        // Calcul de la largeur de la barre (60% de la place disponible)
        double calculatedBarWidth = (availableWidth / numBars) * 0.6;
        // On limite la taille pour éviter que ce soit trop fin ou trop gros
        double finalBarWidth = calculatedBarWidth.clamp(4.0, 24.0);

        double maxVal = 0;
        for (var item in rawBarData) {
          if (item['y'] > maxVal) maxVal = item['y'];
        }
        if (maxVal == 0) maxVal = 1;

        // ✅ ARRONDIR L'AXE Y POUR AVOIR DES CHIFFRES PROPRES
        double interval = 1.0;
        int decimalPlaces = 1;

        if (maxVal <= 0.01) { interval = 0.002; decimalPlaces = 3; }
        else if (maxVal <= 0.05) { interval = 0.01; decimalPlaces = 3; }
        else if (maxVal <= 0.1) { interval = 0.02; decimalPlaces = 2; }
        else if (maxVal <= 0.5) { interval = 0.1; decimalPlaces = 2; }
        else if (maxVal <= 1) { interval = 0.2; decimalPlaces = 1; }
        else if (maxVal <= 5) { interval = 1; decimalPlaces = 1; }
        else if (maxVal <= 10) { interval = 2; decimalPlaces = 1; }
        else if (maxVal <= 50) { interval = 10; decimalPlaces = 0; }
        else { interval = 20; decimalPlaces = 0; }

        // On arrondit le max pour que la plus haute barre ne touche pas le plafond
        double maxY = (maxVal / interval).ceil() * interval;
        if (maxY == maxVal) maxY += interval; 
        if (maxY == 0) maxY = interval;

        final gridColor = isDark ? Colors.white12 : Colors.grey.shade300;

        List<BarChartGroupData> groups = rawBarData.map((item) {
          return BarChartGroupData(
            x: item['x'],
            barRods: [
              BarChartRodData(
                toY: item['y'],
                color: item['y'] > 0 ? _chartColor : Colors.transparent,
                width: finalBarWidth,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              )
            ],
          );
        }).toList();

        return BarChart(
          BarChartData(
            maxY: maxY, 
            barGroups: groups, 
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              show: true, 
              drawVerticalLine: false, 
              horizontalInterval: interval,
              getDrawingHorizontalLine: (value) => FlLine(color: gridColor, strokeWidth: 1, dashArray: [5, 5])
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true, 
                  reservedSize: 45, 
                  interval: interval,
                  getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(decimalPlaces), style: const TextStyle(color: Colors.grey, fontSize: 11))
                )
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true, 
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) {
                    String text = value.toInt().toString();
                    if (_selectedPeriod == PeriodType.year) {
                      final months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
                      if (value > 0 && value <= 12) text = months[value.toInt() - 1];
                    } else if (_selectedPeriod == PeriodType.month) {
                      if (value % 5 != 0 && value != 1) return const SizedBox.shrink();
                    }
                    return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(text, style: const TextStyle(color: Colors.grey, fontSize: 11)));
                  }
                ),
              ),
            ),
            borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: gridColor, width: 1), left: BorderSide(color: gridColor, width: 1))),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (group) => Theme.of(context).cardColor, 
                tooltipBorder: BorderSide(color: gridColor), 
                tooltipPadding: const EdgeInsets.all(8),
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  if (rod.toY == 0) return null; 
                  String dateStr = "";
                  if (_selectedPeriod == PeriodType.month) dateStr = "Le ${group.x}";
                  if (_selectedPeriod == PeriodType.year) dateStr = "Mois ${group.x}";
                  if (_selectedPeriod == PeriodType.total) dateStr = "Année ${group.x}";
                  
                  return BarTooltipItem(
                    '$dateStr\n', 
                    const TextStyle(color: Colors.grey, fontSize: 11),
                    children: [TextSpan(text: '${rod.toY.toStringAsFixed(3)} kWh', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 12))],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor, 
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: isDark ? Colors.white : Colors.black87)),
        ],
      ),
    );
  }
}

class GaugePainter extends CustomPainter {
  final double value;
  final double maxValue;
  final double alertThreshold;
  final Color bgColor;
  final Color needleColor;

  GaugePainter({
    required this.value, 
    required this.maxValue, 
    required this.alertThreshold,
    required this.bgColor,
    required this.needleColor
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 10;
    const startAngle = pi;
    const sweepAngle = pi;

    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, bgPaint);

    final percent = (value / maxValue).clamp(0.0, 1.0);
    final valuePaint = Paint()
      ..color = value > alertThreshold ? Colors.red : const Color(0xFFE67E22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle * percent, false, valuePaint);

    final needleAngle = pi + (pi * percent);
    final needleEnd = Offset(
      center.dx + (radius - 20) * cos(needleAngle),
      center.dy + (radius - 20) * sin(needleAngle),
    );
    
    final needlePaint = Paint()
      ..color = needleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawLine(center, needleEnd, needlePaint);
    canvas.drawCircle(center, 6, Paint()..color = needleColor);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}