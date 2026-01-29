import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:intl/intl.dart'; 
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart'; 
import '../local_db.dart'; 

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool _isLoading = true;

  // --- DATA VARIABLES ---
  int _countNew = 0;
  int _countLearning = 0;
  int _countLearned = 0; 
  int _touchedIndex = -1;

  List<FlSpot> _learnedSpots = [];   
  List<FlSpot> _learningSpots = []; 
  List<String> _dateLabels = [];     
  double _historyMaxY = 10;

  int _freshCount = 0;
  int _fadingCount = 0;
  int _dormantCount = 0;

  List<int> _forecastCounts = List.filled(7, 0);

  Map<DateTime, int> _heatmapData = {};
  DateTime _selectedHeatmapDate = DateTime.now(); 
  int _selectedHeatmapScore = 0;

  // 🔥 THEME COLORS (Strict Orange/Black)
  final Color _cBlack = const Color(0xFF121212);     
  final Color _cCard  = const Color(0xFF1E1E1E);     
  final Color _cOrange = const Color(0xFFFF9800);    
  final Color _cDarkOrange = const Color(0xFFE65100);
  final Color _cGrey = const Color(0xFF424242);      

  @override
  void initState() {
    super.initState();
    _loadAllData();
    LocalDB.instance.onDatabaseChanged.addListener(_onDatabaseChanged);
  }

  @override
  void dispose() {
    LocalDB.instance.onDatabaseChanged.removeListener(_onDatabaseChanged);
    super.dispose();
  }

  void _onDatabaseChanged() {
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    final db = await LocalDB.instance.database;
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    
    final userId = Supabase.instance.client.auth.currentUser?.id;

    // --- 1. LOCAL DATA ---
    final allWords = await db.query('user_progress');
    final totalWordsRes = await db.rawQuery('SELECT COUNT(*) FROM words');
    int totalWords = Sqflite.firstIntValue(totalWordsRes) ?? 0;

    int lrn = 0, lrd = 0;
    int fresh = 0, fading = 0, dormant = 0;
    List<int> forecast = List.filled(7, 0);

    for (var row in allWords) {
      String status = row['status'] as String;
      
      if (status == 'learning') lrn++;
      else if (status == 'consolidating' || status == 'learned') {
        lrd++;
        if (row['last_reviewed'] != null) {
          final lastReview = DateTime.parse(row['last_reviewed'] as String).toLocal();
          final diff = now.difference(lastReview).inDays;
          if (diff <= 7) fresh++;
          else if (diff <= 30) fading++;
          else dormant++;
        }
      }

      if (row['next_due_at'] != null) {
        DateTime due = DateTime.parse(row['next_due_at'] as String).toLocal();
        DateTime dueMidnight = DateTime(due.year, due.month, due.day);
        int diffDays = dueMidnight.difference(todayMidnight).inDays;

        if (diffDays < 0) forecast[0]++;       
        else if (diffDays < 7) forecast[diffDays]++; 
      }
    }

    int n = totalWords - (lrn + lrd);
    if (n < 0) n = 0;

    // HEATMAP
    final logs = await db.query('attempt_logs');
    Map<DateTime, int> heat = {};
    for (var log in logs) {
      DateTime dt = DateTime.parse(log['attempted_at'] as String).toLocal();
      DateTime cleanDate = DateTime(dt.year, dt.month, dt.day);
      heat[cleanDate] = (heat[cleanDate] ?? 0) + 1;
    }

    // --- 2. CLOUD DATA (History) ---
    List<FlSpot> tempLearned = [];
    List<FlSpot> tempLearning = [];
    List<String> tempDates = [];
    double calcMax = 10;

    if (userId != null) {
      try {
        final response = await Supabase.instance.client
            .from('daily_stats')
            .select('date, learned_count, reviewing_count') 
            .eq('user_id', userId)
            .order('date', ascending: true)
            .limit(30);

        int index = 0;
        for (var row in response) {
          double valLearned = (row['learned_count'] as num).toDouble();
          double valLearning = (row['reviewing_count'] as num).toDouble();
          
          tempLearned.add(FlSpot(index.toDouble(), valLearned));
          tempLearning.add(FlSpot(index.toDouble(), valLearning));
          
          DateTime dateObj = DateTime.parse(row['date']);
          tempDates.add(DateFormat('MMM d').format(dateObj));

          if (valLearned > calcMax) calcMax = valLearned;
          if (valLearning > calcMax) calcMax = valLearning;
          index++;
        }
      } catch (e) {
        debugPrint("⚠️ Could not load history: $e");
      }
    }

    if (tempLearned.isEmpty) {
      tempLearned.add(const FlSpot(0, 0));
      tempLearning.add(const FlSpot(0, 0));
      tempDates.add("Today");
    }

    if (mounted) {
      setState(() {
        _countNew = n;
        _countLearning = lrn;
        _countLearned = lrd;
        _freshCount = fresh;
        _fadingCount = fading;
        _dormantCount = dormant;
        _forecastCounts = forecast;
        _learnedSpots = tempLearned;
        _learningSpots = tempLearning;
        _dateLabels = tempDates;
        _historyMaxY = calcMax * 1.2;
        _heatmapData = heat;
        
        DateTime todayClean = DateTime(now.year, now.month, now.day);
        if (_selectedHeatmapScore == 0) {
           _selectedHeatmapDate = todayClean;
           _selectedHeatmapScore = heat[todayClean] ?? 0;
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(backgroundColor: _cBlack, body: Center(child: CircularProgressIndicator(color: _cOrange)));

    int totalActive = _countLearning + _countLearned;
    double retention = totalActive == 0 ? 0 : (_freshCount / totalActive) * 100;

    return Scaffold(
      backgroundColor: _cBlack,
      appBar: AppBar(
        title: const Text("STATISTICS", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 22, letterSpacing: 1.2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAllData,
        color: _cOrange,
        backgroundColor: _cCard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(), 
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. TOP SUMMARY ROW
              Row(
                children: [
                   Expanded(child: _buildSummaryTile("WORDS", totalActive.toString(), Icons.book)),
                   const SizedBox(width: 12),
                   Expanded(child: _buildSummaryTile("RETENTION", "${retention.toInt()}%", Icons.bolt)),
                   const SizedBox(width: 12),
                   Expanded(child: _buildSummaryTile("DAYS", _heatmapData.length.toString(), Icons.local_fire_department)),
                ],
              ),
              const SizedBox(height: 30),

              // 2. KNOWLEDGE DONUT
              _buildSectionTitle("PROGRESS"),
              _buildDarkCard(
                height: 320,
                child: Column(
                  children: [
                     Expanded(child: _buildDonutChart()),
                     const SizedBox(height: 20),
                     Row(
                       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                       children: [
                         _buildLegendDot("Mastered", _cOrange),
                         _buildLegendDot("Learning", _cDarkOrange),
                         _buildLegendDot("New", _cGrey),
                       ],
                     ),
                     const SizedBox(height: 10),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              
             // 3. HISTORY CHART
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionTitle("VELOCITY"),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      "LAST ${_dateLabels.length} DAYS", 
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.3), 
                        fontWeight: FontWeight.bold, 
                        fontSize: 10
                      )
                    ),
                  ),
                ],
              ),
              _buildDarkCard(
                height: 320, // Increased height slightly for the legend
                padding: const EdgeInsets.fromLTRB(10, 16, 24, 10),
                child: Column(
                  children: [
                    // 🔥 LEGEND ROW
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildLegendDot("Mastered", _cOrange),
                        const SizedBox(width: 16),
                        _buildLegendDot("Learning", _cDarkOrange),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // THE CHART
                    Expanded(child: _buildHistoryChart()),
                  ],
                )
              ),
              const SizedBox(height: 30),
              
              // 4. FUTURE LOAD
              _buildSectionTitle("FORECAST"),
              _buildDarkCard(
                height: 320, 
                // Increased padding at bottom to let labels breathe
                padding: const EdgeInsets.only(top: 40, bottom: 10, left: 16, right: 16),
                child: _buildForecastBarChart()
              ),
              const SizedBox(height: 30),

              // 5. MEMORY HEALTH
              _buildSectionTitle("MEMORY STRENGTH"),
              _buildDarkCard(
                height: 300, 
                // More space at top for the floating numbers
                padding: const EdgeInsets.only(top: 40, bottom: 20, left: 16, right: 16),
                child: _buildFreshnessChart()
              ),
              const SizedBox(height: 30),

              // 6. HEATMAP
              _buildSectionTitle("ACTIVITY"),
              _buildDarkCard(
                padding: const EdgeInsets.all(16), 
                child: Column(
                  children: [
                    _buildHeatmapGraph(),
                    const Divider(color: Colors.white10, height: 20),
                    _buildHeatmapDetailRow(),
                  ],
                )
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ================= UI WIDGETS =================

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 10.0),
      child: Text(
        title, 
        style: TextStyle(
          fontSize: 14, 
          fontWeight: FontWeight.bold, 
          color: _cOrange,
          letterSpacing: 2.0
        )
      )
    );
  }

  Widget _buildDarkCard({double? height, required Widget child, EdgeInsets? padding}) {
    return Container(
      height: height, 
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cCard, 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: Colors.white.withOpacity(0.08)), 
      ), 
      child: child
    );
  }

  Widget _buildSummaryTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cOrange.withOpacity(0.3)), 
      ),
      child: Column(
        children: [
          Icon(icon, color: _cOrange, size: 22),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.5))),
        ],
      ),
    );
  }

  Widget _buildLegendDot(String label, Color color) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))
    ]);
  }

  // ================= CHARTS =================

  Widget _buildHistoryChart() {
    if (_learnedSpots.length < 2) return const Center(child: Text("Not enough data yet.", style: TextStyle(color: Colors.white38)));

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true, 
          drawVerticalLine: false, 
          // Show 4 horizontal grid lines for context
          horizontalInterval: _historyMaxY / 4 == 0 ? 1 : _historyMaxY / 4, 
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          
          // LEFT AXIS: Show numbers
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, 
              reservedSize: 28, 
              getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: const TextStyle(color: Colors.white38, fontSize: 10))
            )
          ),
          
          // 🔥 BOTTOM AXIS: Show Dates
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              // Calculate smart interval to prevent overlapping text
              interval: (_dateLabels.length / 5).ceil().toDouble(), 
              getTitlesWidget: (value, meta) {
                int index = value.toInt();
                // Safety check
                if (index < 0 || index >= _dateLabels.length) return const SizedBox.shrink();
                
                // Only show the first date, last date, and a few in between
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    _dateLabels[index], // e.g. "Jan 12"
                    style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0, maxX: (_learnedSpots.length - 1).toDouble(),
        minY: 0, maxY: _historyMaxY, // Add buffer to top
        
        lineBarsData: [
          // 🟠 Learning Line (Darker)
          LineChartBarData(
            spots: _learningSpots,
            isCurved: true,
            color: _cDarkOrange.withOpacity(0.8),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            // Gradient Fill below the line
            belowBarData: BarAreaData(
              show: true, 
              gradient: LinearGradient(
                colors: [_cDarkOrange.withOpacity(0.1), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            ),
          ),
          
          // 🍊 Mastered Line (Brighter)
          LineChartBarData(
            spots: _learnedSpots,
            isCurved: true,
            color: _cOrange,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            // Gradient Fill below the line
            belowBarData: BarAreaData(
              show: true, 
              gradient: LinearGradient(
                colors: [_cOrange.withOpacity(0.3), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            ),
          ),
        ],
        // Tooltip logic
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: _cCard,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final bool isLearned = spot.barIndex == 1;
                return LineTooltipItem(
                  "${spot.y.toInt()}", 
                  TextStyle(
                    color: isLearned ? _cOrange : _cDarkOrange, 
                    fontWeight: FontWeight.bold
                  )
                );
              }).toList();
            }
          )
        ),
      ),
    );
  }

  Widget _buildDonutChart() {
    double total = (_countLearned + _countLearning + _countNew).toDouble();
    if (total == 0) total = 1; 

    // 🔥 DYNAMIC CONTENT LOGIC
    String label = "TOTAL";
    String countStr = total.toInt().toString();
    Color textColor = Colors.white;

    if (_touchedIndex == 0) {
      label = "MASTERED";
      countStr = _countLearned.toString();
      textColor = _cOrange;
    } else if (_touchedIndex == 1) {
      label = "LEARNING";
      countStr = _countLearning.toString();
      textColor = _cDarkOrange;
    } else if (_touchedIndex == 2) {
      label = "NEW";
      countStr = _countNew.toString();
      textColor = _cGrey;
    }

    return SizedBox(
      height: 220, // Slightly taller for breathing room
      child: Stack(
        children: [
          PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  setState(() {
                    if (!event.isInterestedForInteractions || pieTouchResponse == null || pieTouchResponse.touchedSection == null) {
                      _touchedIndex = -1; // Reset to Total when letting go
                      return;
                    }
                    _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                  });
                },
              ),
              borderData: FlBorderData(show: false),
              sectionsSpace: 5, // A bit more space between sections looks cleaner
              centerSpaceRadius: 70,
              sections: [
                _buildPieSection(0, _countLearned.toDouble(), _cOrange, total),
                _buildPieSection(1, _countLearning.toDouble(), _cDarkOrange, total),
                _buildPieSection(2, _countNew.toDouble(), _cGrey, total),
              ],
            ),
          ),
          
          // 🔥 ANIMATED CENTER TEXT
          Center(
             child: Column(
               mainAxisSize: MainAxisSize.min,
               children: [
                 AnimatedSwitcher(
                   duration: const Duration(milliseconds: 300),
                   transitionBuilder: (Widget child, Animation<double> animation) {
                     return ScaleTransition(scale: animation, child: child);
                   },
                   child: Text(
                     countStr, 
                     key: ValueKey<String>(countStr), // Key ensures animation triggers
                     style: TextStyle(
                       fontSize: 36, 
                       fontWeight: FontWeight.w900, 
                       color: textColor
                     )
                   ),
                 ),
                 AnimatedSwitcher(
                   duration: const Duration(milliseconds: 300),
                   child: Text(
                     label, 
                     key: ValueKey<String>(label),
                     style: TextStyle(
                       fontSize: 12, 
                       color: textColor.withOpacity(0.7), 
                       fontWeight: FontWeight.bold, 
                       letterSpacing: 2.0
                     )
                   ),
                 ),
               ],
             )
          )
        ],
      ),
    );
  }

 PieChartSectionData _buildPieSection(int index, double value, Color color, double total) {
    final isTouched = index == _touchedIndex;
    // When touched, it grows from 16 to 25
    final double radius = isTouched ? 25.0 : 16.0; 
    
    return PieChartSectionData(
      color: color.withOpacity(isTouched ? 1.0 : 0.8), // Brighten when touched
      value: value, 
      title: '', 
      radius: radius,
    );
  }

  Widget _buildFreshnessChart() {
    int maxVal = max(_freshCount, max(_fadingCount, _dormantCount));
    if (maxVal == 0) maxVal = 10;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxVal * 1.3), 
        barTouchData: BarTouchData(
          enabled: false, // 🚫 NO CLICKING
          touchTooltipData: BarTouchTooltipData(
             tooltipBgColor: Colors.transparent, // 👻 INVISIBLE BG
             tooltipPadding: EdgeInsets.zero,
             tooltipMargin: 2,
             getTooltipItem: (group, groupIndex, rod, rodIndex) {
               return BarTooltipItem(
                 rod.toY.toInt().toString(),
                 const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
               );
             }
          )
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                const style = TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 10);
                String text;
                switch (value.toInt()) {
                  case 0: text = 'RECENT\n< 1 wk'; break;
                  case 1: text = 'SLIPPING\n< 1 mo'; break;
                  case 2: text = 'LOST\n> 1 mo'; break;
                  default: text = '';
                }
                return Padding(padding: const EdgeInsets.only(top: 10), child: Text(text, style: style, textAlign: TextAlign.center));
              },
              reservedSize: 40,
            ),
          ),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: [
          _buildBar(0, _freshCount, _cOrange),
          _buildBar(1, _fadingCount, _cDarkOrange),
          _buildBar(2, _dormantCount, Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildForecastBarChart() {
    final labels = ["Late", "Tmro", "+2d", "+3d", "+4d", "+5d", "+6d"];
    int maxVal = _forecastCounts.reduce(max);
    if(maxVal == 0) maxVal = 5;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        maxY: maxVal.toDouble() + 5, // Extra space on top
        barTouchData: BarTouchData(
          enabled: false, // 🚫 NO CLICKING (Permanent Numbers)
          touchTooltipData: BarTouchTooltipData(
             tooltipBgColor: Colors.transparent, // 👻 INVISIBLE BG
             tooltipPadding: EdgeInsets.zero,
             tooltipMargin: 2,
             getTooltipItem: (group, groupIndex, rod, rodIndex) {
               return BarTooltipItem(
                 "${rod.toY.toInt()}", 
                 const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14) // CLEAN WHITE TEXT
               );
             }
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, 
              reservedSize: 32, // ✅ INCREASED SPACE FOR LABELS
              getTitlesWidget: (value, meta) {
                int idx = value.toInt();
                if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12), 
                  child: Text(labels[idx], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))
                );
              }
            )
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: false),
        barGroups: _forecastCounts.asMap().entries.map((entry) {
          Color barColor = entry.key == 0 ? Colors.redAccent : _cOrange;
          return BarChartGroupData(
            x: entry.key,
            showingTooltipIndicators: entry.value > 0 ? [0] : [], // Only show if > 0
            barRods: [
              BarChartRodData(
                toY: entry.value.toDouble(),
                color: barColor,
                width: 14, 
                borderRadius: BorderRadius.circular(2),
                backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxVal.toDouble() + 5, color: Colors.white.withOpacity(0.05)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  BarChartGroupData _buildBar(int x, int value, Color color) {
    return BarChartGroupData(
      x: x, 
      showingTooltipIndicators: value > 0 ? [0] : [],
      barRods: [
        BarChartRodData(
          toY: value.toDouble(), 
          color: color, 
          width: 25, 
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          backDrawRodData: BackgroundBarChartRodData(show: true, toY: null, color: Colors.white.withOpacity(0.05))
        )
      ]
    );
  }

  Widget _buildHeatmapDetailRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat.yMMMMd().format(_selectedHeatmapDate).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 2),
            const Text("SELECTED DATE", style: TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: _cOrange, borderRadius: BorderRadius.circular(8)),
          child: Text("$_selectedHeatmapScore XP", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        )
      ],
    );
  }

  Widget _buildHeatmapGraph() {
    return SizedBox(
      width: double.infinity,
      child: HeatMap(
        datasets: _heatmapData,
        colorMode: ColorMode.color, 
        scrollable: true,
        showText: false,
        startDate: DateTime.now().subtract(const Duration(days: 60)), 
        endDate: DateTime.now(),
        colorsets: {
          1: _cOrange.withOpacity(0.2),  
          100: _cOrange.withOpacity(0.4),
          200: _cOrange.withOpacity(0.6),                 
          300: _cOrange.withOpacity(0.8),                  
          400: _cOrange,          
        },
        onClick: (value) {
          setState(() {
            _selectedHeatmapDate = value;
            _selectedHeatmapScore = _heatmapData[value] ?? 0;
          });
        },
        defaultColor: Colors.white.withOpacity(0.05),
        textColor: Colors.white,
        showColorTip: false,
        size: 28,
        margin: const EdgeInsets.all(2),
      ),
    );
  }
}