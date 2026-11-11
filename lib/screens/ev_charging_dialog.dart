import 'package:flutter/material.dart';

class EvChargingDialog extends StatefulWidget {
  final List<Map<String, dynamic>> historyData;
  final bool isDark;

  const EvChargingDialog({super.key, required this.historyData, required this.isDark});

  @override
  State<EvChargingDialog> createState() => _EvChargingDialogState();
}

class _EvChargingDialogState extends State<EvChargingDialog> {
  int _lookbackDays = 7;
  double _voltageThreshold = 210.0;
  
  late TextEditingController _thresholdController;

  Map<int, HourStats> _stats = {};

  @override
  void initState() {
    super.initState();
    _thresholdController = TextEditingController(text: _voltageThreshold.toStringAsFixed(0));
    _analyzeData();
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  void _analyzeData() {
    _stats.clear();
    for (int i = 0; i < 24; i++) {
      _stats[i] = HourStats();
    }

    DateTime cutoff = DateTime.now().subtract(Duration(days: _lookbackDays));

    for (var data in widget.historyData) {
      DateTime time = data['time'];
      if (time.isBefore(cutoff)) continue;

      double v = data['v'];
      if (v <= 0) continue;

      int hour = time.hour;
      _stats[hour]!.count++;
      _stats[hour]!.sumV += v;
      if (v < _stats[hour]!.minV) _stats[hour]!.minV = v;
      
      if (v < _voltageThreshold) {
        _stats[hour]!.drops++;
      }
    }
    setState(() {});
  }

  String _getBestWindow() {
    int bestStart = -1;
    int bestLength = 0;
    int currentStart = -1;
    int currentLength = 0;

    for (int k = 0; k < 48; k++) {
      int i = k % 24;
      if (_stats[i]!.drops == 0 && _stats[i]!.count > 0) {
        if (currentLength == 0) currentStart = i;
        currentLength++;
        if (currentLength > bestLength && currentLength <= 24) {
          bestLength = currentLength;
          bestStart = currentStart;
        }
      } else {
        currentLength = 0;
      }
    }

    if (bestLength == 0) return "Aucune plage totalement sûre trouvée.";
    
    int end = (bestStart + bestLength) % 24;
    return "Meilleure plage : ${bestStart.toString().padLeft(2, '0')}:00 à ${end.toString().padLeft(2, '0')}:00 ($bestLength h sûres)";
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final cardColor = widget.isDark ? const Color(0xFF1A1D24) : Colors.white;

    return AlertDialog(
      backgroundColor: cardColor,
      title: Row(
        children: [
          const Icon(Icons.electric_car, color: Colors.green, size: 24), // Taille réduite
          const SizedBox(width: 8), 
          Text('Optimisation Charge VE', style: TextStyle(color: textColor, fontSize: 18)) // Taille réduite
        ]
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _lookbackDays,
                      decoration: const InputDecoration(
                        labelText: 'Période', 
                        labelStyle: TextStyle(fontSize: 12),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      dropdownColor: cardColor,
                      style: TextStyle(color: textColor, fontSize: 13),
                      items: const [
                        DropdownMenuItem(value: 3, child: Text('3 jours')),
                        DropdownMenuItem(value: 7, child: Text('7 jours')),
                        DropdownMenuItem(value: 30, child: Text('30 jours'))
                      ],
                      onChanged: (val) { if (val != null) { setState(() { _lookbackDays = val; }); _analyzeData(); } },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _thresholdController,
                      decoration: const InputDecoration(
                        labelText: 'Seuil critique (V)', 
                        labelStyle: TextStyle(fontSize: 12),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: textColor, fontSize: 13),
                      onChanged: (val) {
                        double? parsed = double.tryParse(val);
                        if (parsed != null && parsed > 0) {
                          _voltageThreshold = parsed;
                          _analyzeData();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity, 
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), border: Border.all(color: Colors.green), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  _getBestWindow(), 
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12), // Taille réduite
                  textAlign: TextAlign.center
                ),
              ),
              const SizedBox(height: 12),
              Text('Détail par heure :', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              ...List.generate(24, (index) {
                final stat = _stats[index]!;
                if (stat.count == 0) return const SizedBox.shrink();

                Color statusColor = stat.drops == 0 ? Colors.green : (stat.drops <= 2 ? Colors.orange : Colors.red);
                String statusText = stat.drops == 0 ? "Sûr" : "${stat.drops} chute(s)";

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3.0), // Espacement réduit
                  child: Row(
                    children: [
                      SizedBox(
                        width: 45,
                        child: Text('${index.toString().padLeft(2, '0')}:00', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Moy: ${stat.avgV.toStringAsFixed(1)}V | Min: ${stat.minV.toStringAsFixed(1)}V', 
                          style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 11), // Taille réduite
                        ),
                      ),
                      Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)), // Taille réduite
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), 
          child: const Text('Fermer', style: TextStyle(color: Colors.grey))
        )
      ],
    );
  }
}

class HourStats {
  int count = 0;
  int drops = 0;
  double minV = 999.0;
  double sumV = 0.0;
  double get avgV => count > 0 ? sumV / count : 0.0;
}