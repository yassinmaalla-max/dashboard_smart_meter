import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportComponent {
  String name;
  DateTime start;
  DateTime end;
  double totalKwh;
  
  ReportComponent({required this.name, required this.start, required this.end, this.totalKwh = 0.0});
}

class ReportDialog extends StatefulWidget {
  final List<Map<String, dynamic>> historyData;
  final bool isDark;
  final List<ReportComponent> initialComponents;
  final Function(int index, bool isStart) onRequestChartSelection;

  const ReportDialog({
    super.key, 
    required this.historyData, 
    required this.isDark,
    required this.initialComponents,
    required this.onRequestChartSelection,
  });

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  late List<ReportComponent> _components;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialComponents.isEmpty) {
      _components = [ReportComponent(name: "Appareil 1", start: DateTime.now().subtract(const Duration(days: 1)), end: DateTime.now())];
    } else {
      _components = List.from(widget.initialComponents);
    }
  }

  void _updateComponentCount(int count) {
    setState(() {
      if (_components.length < count) {
        for (int i = _components.length; i < count; i++) {
          _components.add(ReportComponent(
            name: "Appareil ${i + 1}",
            start: DateTime.now().subtract(const Duration(days: 1)),
            end: DateTime.now(),
          ));
        }
      } else if (_components.length > count) {
        _components.removeRange(count, _components.length);
      }
    });
  }

  Future<void> _pickDateTime(ReportComponent comp, bool isStart) async {
    DateTime initial = isStart ? comp.start : comp.end;
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (pickedDate != null) {
      if (!mounted) return;
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initial),
      );

      if (pickedTime != null) {
        setState(() {
          DateTime newDateTime = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
          if (isStart) comp.start = newDateTime;
          else comp.end = newDateTime;
        });
      }
    }
  }

  void _calculateConsumption() {
    for (var comp in _components) {
      double totalKwh = 0.0;
      for (int i = 1; i < widget.historyData.length; i++) {
        DateTime currTime = widget.historyData[i]['time'];
        if (currTime.isAfter(comp.start) && currTime.isBefore(comp.end)) {
          double hoursDiff = currTime.difference(widget.historyData[i-1]['time']).inSeconds / 3600.0;
          if (hoursDiff > 0 && hoursDiff <= (10.0 / 60.0)) {
            totalKwh += (widget.historyData[i]['p'] * hoursDiff) / 1000.0;
          }
        }
      }
      comp.totalKwh = totalKwh;
    }
  }

  Future<void> _generatePdf() async {
    setState(() => _isGenerating = true);
    _calculateConsumption();

    final pdf = pw.Document();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    // ✅ 1. CALCUL DES TOTAUX
    double totalRealKwh = _components.fold(0.0, (sum, comp) => sum + comp.totalKwh);
    double totalMoyJour = 0.0;
    double totalMoyMois = 0.0;
    double totalDuration = 0.0;

    List<List<dynamic>> tableData = [];

    for (var comp in _components) {
      // Calcul de la durée
      double durationHours = comp.end.difference(comp.start).inMinutes / 60.0;
      if (durationHours <= 0.01) durationHours = 0.01;
      double durationDays = durationHours / 24.0;
      if (durationDays <= 0.01) durationDays = 1.0;
      
      double moyJour = comp.totalKwh / durationDays;
      double moyMois = moyJour * 30;
      
      // ✅ 2. CALCUL DU POURCENTAGE
      double percent = totalRealKwh > 0 ? (comp.totalKwh / totalRealKwh) * 100 : 0.0;

      totalDuration += durationHours;
      totalMoyJour += moyJour;
      totalMoyMois += moyMois;

      tableData.add([
        pw.Text(comp.name, style: const pw.TextStyle(fontSize: 9)),
        pw.Text('${dateFormat.format(comp.start)}\nau ${dateFormat.format(comp.end)}', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('${durationHours.toStringAsFixed(1)} h', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('${comp.totalKwh.toStringAsFixed(3)} kWh', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('${moyJour.toStringAsFixed(3)} kWh', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('${moyMois.toStringAsFixed(2)} kWh', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('${percent.toStringAsFixed(1)} %', style: const pw.TextStyle(fontSize: 9)),
      ]);
    }

    // ✅ 3. AJOUT DE LA LIGNE TOTAL
    tableData.add([
      pw.Text('TOTAL', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      pw.Text('', style: const pw.TextStyle(fontSize: 9)),
      pw.Text('${totalDuration.toStringAsFixed(1)} h', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      pw.Text('${totalRealKwh.toStringAsFixed(3)} kWh', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      pw.Text('${totalMoyJour.toStringAsFixed(3)} kWh', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      pw.Text('${totalMoyMois.toStringAsFixed(2)} kWh', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      pw.Text('100 %', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
    ]);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Rapport de Consommation', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Généré le: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
                ]
              )
            ),
            pw.SizedBox(height: 20),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(2), // Appareil
                1: const pw.FlexColumnWidth(3), // Période
                2: const pw.FlexColumnWidth(1.5), // Durée
                3: const pw.FlexColumnWidth(2), // Conso
                4: const pw.FlexColumnWidth(2), // Moy Jour
                5: const pw.FlexColumnWidth(2), // Moy Mois
                6: const pw.FlexColumnWidth(1.5), // Part (%)
              },
              children: [
                // En-tête
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.orange800),
                  children: [
                    _buildHeaderCell('Appareil'),
                    _buildHeaderCell('Période'),
                    _buildHeaderCell('Durée (h)'),
                    _buildHeaderCell('Conso. Réelle'),
                    _buildHeaderCell('Moy. / Jour'),
                    _buildHeaderCell('Moy. / Mois'),
                    _buildHeaderCell('Part (%)'),
                  ],
                ),
                // Données
                ...tableData.map((row) {
                  return pw.TableRow(
                    children: row.map<pw.Widget>((cell) {
                      // On ajoute un peu de padding
                      return pw.Padding(padding: const pw.EdgeInsets.all(4), child: cell);
                    }).toList(),
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 30),
            pw.Text('Note : Les moyennes sont calculées sur la base de la consommation réelle mesurée par le Smart Meter sur la période sélectionnée.', 
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Rapport_Conso_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );

    if (mounted) {
      Navigator.pop(context, _components);
      setState(() => _isGenerating = false);
    }
  }

  pw.Widget _buildHeaderCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text, 
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final cardColor = widget.isDark ? const Color(0xFF1A1D24) : Colors.white;

    return AlertDialog(
      backgroundColor: cardColor,
      title: Text('Créer un rapport', style: TextStyle(color: textColor)),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('Nombre d\'appareils : ', style: TextStyle(color: textColor)),
                  DropdownButton<int>(
                    value: _components.length,
                    dropdownColor: cardColor,
                    style: TextStyle(color: textColor),
                    items: [1, 2, 3, 4, 5, 6].map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
                    onChanged: (val) { if (val != null) _updateComponentCount(val); },
                  ),
                ],
              ),
              const Divider(),
              ..._components.asMap().entries.map((entry) {
                int index = entry.key;
                ReportComponent comp = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        style: TextStyle(color: textColor),
                        decoration: const InputDecoration(labelText: 'Nom de l\'appareil', isDense: true),
                        controller: TextEditingController(text: comp.name),
                        onChanged: (val) => comp.name = val,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _pickDateTime(comp, true),
                                    icon: const Icon(Icons.calendar_today, size: 14, color: Colors.green),
                                    label: Text('Début: ${DateFormat('dd/MM HH:mm').format(comp.start)}', style: const TextStyle(fontSize: 12, color: Colors.green)),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.touch_app, size: 20, color: Colors.orange),
                                    tooltip: 'Sélectionner sur le graphique',
                                    onPressed: () {
                                      Navigator.pop(context, _components);
                                      widget.onRequestChartSelection(index, true); 
                                    },
                                  )
                                ],
                              ),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _pickDateTime(comp, false),
                                    icon: const Icon(Icons.calendar_today, size: 14, color: Colors.red),
                                    label: Text('Fin: ${DateFormat('dd/MM HH:mm').format(comp.end)}', style: const TextStyle(fontSize: 12, color: Colors.red)),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.touch_app, size: 20, color: Colors.orange),
                                    tooltip: 'Sélectionner sur le graphique',
                                    onPressed: () {
                                      Navigator.pop(context, _components); 
                                      widget.onRequestChartSelection(index, false);
                                    },
                                  )
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _components),
          child: const Text('Fermer', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE67E22)),
          onPressed: _isGenerating ? null : _generatePdf,
          icon: _isGenerating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.picture_as_pdf),
          label: Text(_isGenerating ? 'Génération...' : 'Générer le PDF'),
        ),
      ],
    );
  }
}