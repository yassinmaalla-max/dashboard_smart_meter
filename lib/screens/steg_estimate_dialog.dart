import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class StegEstimateDialog extends StatefulWidget {
  final List<Map<String, dynamic>> historyData;
  final bool isDark;

  const StegEstimateDialog({
    super.key,
    required this.historyData,
    required this.isDark,
  });

  @override
  State<StegEstimateDialog> createState() => _StegEstimateDialogState();
}

class _StegEstimateDialogState extends State<StegEstimateDialog> {
  late DateTime _startDate;
  late DateTime _endDate;
  int _selectedMonths = 2; 
  
  bool _isForecast = false;
  bool _includeSolar = true;
  int _selectedAmperage = 32;

  // ✅ Nouveaux paramètres pour la production
  String _prodMode = 'auto'; // 'auto', 'daily', 'total'
  late TextEditingController _prodDailyController;
  late TextEditingController _prodTotalController;
  double _manualProdDaily = 0.0;
  double _manualProdTotal = 0.0;

  // Résultats du calcul
  double _totalKwh = 0.0;
  double _totalProd = 0.0;
  int _totalDays = 0;
  int _daysWithData = 0;

  final Map<int, double> _ampToKva = {
    10: 2.0, 16: 3.0, 20: 4.0, 32: 7.0, 40: 9.0, 60: 12.0,
  };

  double get _kva => _ampToKva[_selectedAmperage] ?? 7.0;

  @override
  void initState() {
    super.initState();
    _endDate = DateTime.now();
    _startDate = DateTime.now().subtract(const Duration(days: 60));
    _prodDailyController = TextEditingController(text: '0');
    _prodTotalController = TextEditingController(text: '0');
    _calculateStats();
  }

  @override
  void dispose() {
    _prodDailyController.dispose();
    _prodTotalController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        _calculateStats();
      });
    }
  }

  void _updatePeriod(int months) {
    setState(() {
      _selectedMonths = months;
      _calculateStats();
    });
  }

  // ✅ LOGIQUE DE CALCUL
  void _calculateStats() {
    int targetMonth = _startDate.month + _selectedMonths;
    int targetYear = _startDate.year + (targetMonth - 1) ~/ 12;
    targetMonth = (targetMonth - 1) % 12 + 1;
    
    int targetDay = _startDate.day;
    int maxDaysInMonth = DateUtils.getDaysInMonth(targetYear, targetMonth);
    if (targetDay > maxDaysInMonth) targetDay = maxDaysInMonth;
    
    _endDate = DateTime(targetYear, targetMonth, targetDay);

    _totalDays = _endDate.difference(_startDate).inDays + 1;
    if (_totalDays <= 0) _totalDays = 1;

    double sumKwh = 0.0;
    double sumProd = 0.0;
    _daysWithData = 0;
    
    Set<String> uniqueDays = {};

    for (int i = 1; i < widget.historyData.length; i++) {
      DateTime currTime = widget.historyData[i]['time'];
      
      if (currTime.isAfter(_startDate) && currTime.isBefore(_endDate.add(const Duration(days: 1)))) {
        double hoursDiff = currTime.difference(widget.historyData[i-1]['time']).inSeconds / 3600.0;
        
        if (hoursDiff > 0 && hoursDiff <= (10.0 / 60.0)) {
          sumKwh += (widget.historyData[i]['p'] * hoursDiff) / 1000.0;
          sumProd += (widget.historyData[i]['p_prod'] * hoursDiff) / 1000.0;
          
          String dayKey = DateFormat('yyyy-MM-dd').format(currTime);
          uniqueDays.add(dayKey);
        }
      }
    }

    _daysWithData = uniqueDays.length;

    // Calcul de la consommation
    if (_isForecast) {
      if (_daysWithData > 0) {
        double avgDailyKwh = sumKwh / _daysWithData;
        _totalKwh = avgDailyKwh * _totalDays;
      } else {
        _totalKwh = 0.0;
      }
    } else {
      _totalKwh = sumKwh;
    }

    // ✅ NOUVELLE LOGIQUE DE CALCUL POUR LA PRODUCTION
    if (!_includeSolar) {
      _totalProd = 0.0;
    } else {
      switch (_prodMode) {
        case 'daily':
          _totalProd = _manualProdDaily * _totalDays;
          break;
        case 'total':
          _totalProd = _manualProdTotal;
          break;
        case 'auto':
        default:
          if (_isForecast && _daysWithData > 0) {
            _totalProd = (sumProd / _daysWithData) * _totalDays;
          } else {
            _totalProd = sumProd;
          }
          break;
      }
    }
    
    setState(() {});
  }

  // Calculs Tarifaires STEG
  double get _netConsumption => (_totalKwh - _totalProd).clamp(0.0, double.infinity);
  double get _months => _totalDays / 30.0;
  double get _monthlyConsumption => _netConsumption / (_months > 0 ? _months : 1);

  double get _energyPriceMillimes {
    if (_monthlyConsumption <= 50) return 62;
    if (_monthlyConsumption <= 100) return 96;
    if (_monthlyConsumption <= 200) return 176;
    if (_monthlyConsumption <= 300) return 218;
    if (_monthlyConsumption <= 500) return 341;
    return 414;
  }

  double get _tvaRate => _monthlyConsumption <= 300 ? 0.07 : 0.13;

  double get _energyCost => (_netConsumption * _energyPriceMillimes) / 1000;
  double get _powerFee => _kva * 0.700 * _months;
  double get _clFee => (_netConsumption * 5) / 1000;
  double get _fteFee => (_monthlyConsumption <= 100) ? 0.0 : (_netConsumption * 5) / 1000;
  double get _rttFee => 2.944 * _months;

  double get _tvaEnergy => _energyCost * _tvaRate;
  double get _tvaPower => _powerFee * 0.19;
  double get _tvaOther => (_clFee + _fteFee + _rttFee) * _tvaRate;

  double get _totalBeforeTva => _energyCost + _powerFee + _clFee + _fteFee + _rttFee;
  double get _totalTva => _tvaEnergy + _tvaPower + _tvaOther;
  double get _totalTtc => _totalBeforeTva + _totalTva;

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final cardColor = widget.isDark ? const Color(0xFF1A1D24) : Colors.white;
    final df = NumberFormat.currency(locale: 'fr_TN', symbol: 'DT', decimalDigits: 3);

    return AlertDialog(
      backgroundColor: cardColor,
      title: Text('Estimation Facture STEG', style: TextStyle(color: textColor)),
      content: SizedBox(
        width: 550,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ SÉLECTION DE LA DATE ET DE LA PÉRIODE
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 14),
                      label: Text('Début: ${DateFormat('dd/MM/yy').format(_startDate)}', style: TextStyle(color: textColor, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _selectedMonths,
                          isExpanded: true,
                          dropdownColor: cardColor,
                          style: TextStyle(color: textColor, fontSize: 13),
                          items: const [
                            DropdownMenuItem(value: 2, child: Text('2 Mois')),
                            DropdownMenuItem(value: 3, child: Text('3 Mois')),
                            DropdownMenuItem(value: 4, child: Text('4 Mois')),
                            DropdownMenuItem(value: 6, child: Text('6 Mois')),
                            DropdownMenuItem(value: 12, child: Text('1 An')),
                          ],
                          onChanged: (val) {
                            if (val != null) _updatePeriod(val);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Jusqu\'au : ${DateFormat('dd/MM/yyyy').format(_endDate)} ($_totalDays jours)',
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),

              // ✅ MODE PRÉVISION
              Container(
                decoration: BoxDecoration(
                  color: _isForecast ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                  border: Border.all(color: _isForecast ? Colors.blue : Colors.grey.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: CheckboxListTile(
                  title: const Text('Mode Prévision', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('Extrapole sur $_totalDays jours (basé sur $_daysWithData jours de données réelles)', style: const TextStyle(fontSize: 11)),
                  value: _isForecast,
                  onChanged: (val) {
                    setState(() {
                      _isForecast = val ?? false;
                      _calculateStats(); // J'ai corrigé un typo ici (CalculatedStats -> calculateStats)
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
              ),
              const SizedBox(height: 12),

              // ✅ PARAMÈTRES (Production et Ampérage)
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedAmperage,
                      decoration: const InputDecoration(labelText: 'Ampérage', isDense: true),
                      dropdownColor: cardColor,
                      style: TextStyle(color: textColor),
                      items: _ampToKva.keys.map((amp) => DropdownMenuItem(value: amp, child: Text('$amp A (${_ampToKva[amp]?.toInt()} kVA)', style: TextStyle(color: textColor, fontSize: 12)))).toList(),
                      onChanged: (val) { if (val != null) setState(() => _selectedAmperage = val); },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Checkbox(
                          value: _includeSolar,
                          onChanged: (val) {
                            setState(() {
                              _includeSolar = val ?? true;
                              _calculateStats();
                            });
                          },
                        ),
                        const Text('Déduire Prod.', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),

              // ✅ NOUVELLE SECTION PRODUCTION (Toujours visible si la case est cochée)
              if (_includeSolar) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Source Prod. : ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _prodMode,
                      dropdownColor: cardColor,
                      style: TextStyle(color: textColor, fontSize: 13),
                      underline: Container(),
                      items: const [
                        DropdownMenuItem(value: 'auto', child: Text('Automatique (Données)')),
                        DropdownMenuItem(value: 'daily', child: Text('Manuel (Moy. / jour)')),
                        DropdownMenuItem(value: 'total', child: Text('Manuel (Total)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _prodMode = val;
                            _calculateStats();
                          });
                        }
                      },
                    ),
                  ],
                ),
                if (_prodMode == 'daily') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _prodDailyController,
                    decoration: const InputDecoration(labelText: 'Moyenne Prod. Solaire (kWh/jour)', isDense: true),
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textColor),
                    onChanged: (val) {
                      _manualProdDaily = double.tryParse(val) ?? 0.0;
                      _calculateStats();
                    },
                  ),
                ] else if (_prodMode == 'total') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _prodTotalController,
                    decoration: const InputDecoration(labelText: 'Total Prod. Solaire sur la période (kWh)', isDense: true),
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textColor),
                    onChanged: (val) {
                      _manualProdTotal = double.tryParse(val) ?? 0.0;
                      _calculateStats();
                    },
                  ),
                ]
              ],

              const Divider(height: 30),
              
              // ✅ RÉSULTATS
              _buildResultRow('Période analysée', '$_totalDays jours', textColor),
              _buildResultRow('Consommation brute', '${_totalKwh.toStringAsFixed(1)} kWh', textColor),
              if (_totalProd > 0)
                _buildResultRow('Production déduite', '- ${_totalProd.toStringAsFixed(1)} kWh', textColor, color: Colors.green),
              _buildResultRow('Consommation nette', '${_netConsumption.toStringAsFixed(1)} kWh', textColor, isBold: true),
              _buildResultRow('Moyenne mensuelle', '${_monthlyConsumption.toStringAsFixed(1)} kWh', textColor),
              _buildResultRow('Tranche tarifaire', '${_energyPriceMillimes.toStringAsFixed(0)} mill/kWh', textColor),
              
              const Divider(),
              _buildResultRow('Énergie', df.format(_energyCost), textColor),
              _buildResultRow('Redevance Fixe (${_kva.toInt()} kVA)', df.format(_powerFee), textColor),
              _buildResultRow('Taxes (CL, FTE, RTT)', df.format(_clFee + _fteFee + _rttFee), textColor),
              
              const Divider(),
              _buildResultRow('Total HT', df.format(_totalBeforeTva), textColor, isBold: true),
              _buildResultRow('TVA', df.format(_totalTva), textColor),
              
              const Divider(),
              _buildResultRow('TOTAL TTC ESTIMÉ', df.format(_totalTtc), textColor, isBold: true, color: Colors.orange),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  Widget _buildResultRow(String label, String value, Color textColor, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: textColor, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(color: color ?? textColor, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}