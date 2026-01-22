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

  @override
  void initState() {
    super.initState();
    _loadAllData();

    // 🚨 ADD LISTENER: Automatically reload when DB changes
    LocalDB.instance.onDatabaseChanged.addListener(_onDatabaseChanged);
  }

  @override
  void dispose() {
    // 🚨 CLEANUP: Stop listening when we leave
    LocalDB.instance.onDatabaseChanged.removeListener(_onDatabaseChanged);
    super.dispose();
  }

  // Simple wrapper to match the listener signature
  void _onDatabaseChanged() {
    debugPrint("👂 Stats Page heard the bell. Reloading...");
    _loadAllData();
  }

Future<void> _loadAllData() async {
    final db = await LocalDB.instance.database;
    final now = DateTime.now();
    // 1. Create a "Midnight" version of today for fair comparison
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
      
      // Snapshot Counts
      if (status == 'learning') lrn++;
      else if (status == 'consolidating' || status == 'learned') {
        lrd++;
        // Freshness Logic
        if (row['last_reviewed'] != null) {
          final lastReview = DateTime.parse(row['last_reviewed'] as String).toLocal();
          final diff = now.difference(lastReview).inDays;
          if (diff <= 7) fresh++;
          else if (diff <= 30) fading++;
          else dormant++;
        }
      }

      // 🚨 FIX: Forecast Logic (Use Calendar Days)
      if (row['next_due_at'] != null) {
        DateTime due = DateTime.parse(row['next_due_at'] as String).toLocal();
        DateTime dueMidnight = DateTime(due.year, due.month, due.day);
        
        // Compare dates, not hours
        int diffDays = dueMidnight.difference(todayMidnight).inDays;

        if (diffDays < 0) forecast[0]++;       // Overdue (Late)
        else if (diffDays < 7) forecast[diffDays]++; // 0=Today, 1=Tmrw...
      }
    }

    int n = totalWords - (lrn + lrd);
    if (n < 0) n = 0;

    final logs = await db.query('attempt_logs');
    Map<DateTime, int> heat = {};
    for (var log in logs) {
      DateTime dt = DateTime.parse(log['attempted_at'] as String).toLocal();
      DateTime cleanDate = DateTime(dt.year, dt.month, dt.day);
      heat[cleanDate] = (heat[cleanDate] ?? 0) + 1;
    }

    // --- 2. CLOUD DATA ---
    List<FlSpot> tempLearned = [];
    List<FlSpot> tempLearning = [];
    List<String> tempDates = [];
    double calcMax = 10;

    if (userId != null) {
      try {
        final response = await Supabase.instance.client
            .from('daily_stats')
            .select('date, total_learned, total_learning')
            .eq('user_id', userId)
            .order('date', ascending: true)
            .limit(30);

        int index = 0;
        for (var row in response) {
          double valLearned = (row['total_learned'] as num).toDouble();
          double valLearning = (row['total_learning'] as num).toDouble();
          
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
    debugPrint("📊 Stats Reloaded: Forecast is $forecast");
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
        _selectedHeatmapDate = todayClean;
        _selectedHeatmapScore = heat[todayClean] ?? 0;
        _isLoading = false;
      });
    }
  }

  // ================= MAIN BUILD =================

@override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: AppColors.background, body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Complete Insights", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      // 1. WRAP WITH REFRESH INDICATOR
      body: RefreshIndicator(
        onRefresh: _loadAllData, // <--- CALLS YOUR DATA LOADER
        color: AppColors.primary,
        backgroundColor: AppColors.cardColor,
        child: SingleChildScrollView(
          // 2. IMPORTANT: Physics ensures you can always pull, even if content is short
          physics: const AlwaysScrollableScrollPhysics(), 
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ... (Keep all your existing children exactly the same) ...
              _buildHeader("Knowledge Snapshot"),
              _buildCard(height: 280, child: _buildDonutChart()),
              const SizedBox(height: 24),
              
              _buildHeader("Learning Velocity"),
            const Text("Green: Mastered | Amber: In Progress", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 10),
            _buildCard(
              height: 260, 
              padding: const EdgeInsets.fromLTRB(10, 24, 24, 10), 
              child: _buildHistoryChart()
            ),
            const SizedBox(height: 24),

            // 3. FRESHNESS
            _buildHeader("Memory Health"),
            const Text("Don't let your words rot!", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 10),
            _buildCard(height: 260, padding: const EdgeInsets.fromLTRB(16, 24, 24, 10), child: _buildFreshnessChart()),
            const SizedBox(height: 24),

            // 4. FORECAST
            _buildHeader("Future Review Load"),
            _buildCard(height: 240, child: _buildForecastBarChart()),
            const SizedBox(height: 24),

            // 5. CONSISTENCY
            _buildHeader("Consistency Streak"),
            _buildCard(
              padding: const EdgeInsets.all(16), 
              child: Column(
                children: [
                  _buildHeatmapDetailBox(),
                  const SizedBox(height: 15),
                  _buildHeatmapGraph(),
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

  // ================= CHART WIDGETS =================

  // 1. DUAL LINE CHART (History)
  Widget _buildHistoryChart() {
    if (_learnedSpots.length < 2) {
       return const Center(child: Text("Play more days to see your trend!", style: TextStyle(color: AppColors.textSecondary)));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true, 
          drawVerticalLine: false, 
          horizontalInterval: _historyMaxY / 5,
          getDrawingHorizontalLine: (value) => FlLine(color: AppColors.textSecondary.withOpacity(0.1), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)))),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: 0, maxX: (_learnedSpots.length - 1).toDouble(),
        minY: 0, maxY: _historyMaxY,
        lineBarsData: [
          LineChartBarData(
            spots: _learningSpots,
            isCurved: true,
            color: Colors.amber,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: Colors.amber.withOpacity(0.1)),
          ),
          LineChartBarData(
            spots: _learnedSpots,
            isCurved: true,
            color: AppColors.success,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [AppColors.success.withOpacity(0.3), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: AppColors.cardColor,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                bool isLearned = spot.barIndex == 1; 
                String label = isLearned ? "Mastered" : "Learning";
                String date = "";
                if (spot.x.toInt() < _dateLabels.length) date = " (${_dateLabels[spot.x.toInt()]})";
                return LineTooltipItem("$label: ${spot.y.toInt()}$date", TextStyle(color: isLearned ? AppColors.success : Colors.amber, fontWeight: FontWeight.bold));
              }).toList();
            }
          )
        ),
      ),
    );
  }

  // 2. DONUT CHART
  Widget _buildDonutChart() {
    double total = (_countLearned + _countLearning + _countNew).toDouble();
    if (total == 0) total = 1; 

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  setState(() {
                    if (!event.isInterestedForInteractions || pieTouchResponse == null || pieTouchResponse.touchedSection == null) {
                      _touchedIndex = -1;
                      return;
                    }
                    _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                  });
                },
              ),
              borderData: FlBorderData(show: false),
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: [
                _buildPieSection(0, _countLearned.toDouble(), AppColors.success, "Mastered", total),
                _buildPieSection(1, _countLearning.toDouble(), Colors.amber, "Learning", total),
                _buildPieSection(2, _countNew.toDouble(), AppColors.textSecondary.withOpacity(0.3), "Unseen", total),
              ],
            ),
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLegendItem(AppColors.success, "Mastered ($_countLearned)"),
            const SizedBox(height: 8),
            _buildLegendItem(Colors.amber, "Learning ($_countLearning)"),
            const SizedBox(height: 8),
            _buildLegendItem(AppColors.textSecondary.withOpacity(0.3), "Unseen ($_countNew)"),
          ],
        ),
        const SizedBox(width: 10),
      ],
    );
  }

  PieChartSectionData _buildPieSection(int index, double value, Color color, String title, double total) {
    final isTouched = index == _touchedIndex;
    final radius = isTouched ? 60.0 : 50.0;
    final pct = ((value / total) * 100).toInt();
    return PieChartSectionData(color: color, value: value, title: pct > 5 ? '$pct%' : '', radius: radius, titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 12));
  }

  // 3. FRESHNESS CHART
  Widget _buildFreshnessChart() {
    int maxVal = max(_freshCount, max(_fadingCount, _dormantCount));
    if (maxVal == 0) maxVal = 10;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxVal * 1.2),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
             tooltipBgColor: AppColors.cardColor,
             getTooltipItem: (group, groupIndex, rod, rodIndex) {
               String label = groupIndex == 0 ? "Fresh" : (groupIndex == 1 ? "Fading" : "Dormant");
               return BarTooltipItem("$label\n${rod.toY.toInt()}", const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold));
             }
          )
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                const style = TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12);
                String text;
                switch (value.toInt()) {
                  case 0: text = 'Fresh\n(<7d)'; break;
                  case 1: text = 'Fading\n(7-30d)'; break;
                  case 2: text = 'Dormant\n(>30d)'; break;
                  default: text = '';
                }
                return Padding(padding: const EdgeInsets.only(top: 8), child: Text(text, style: style, textAlign: TextAlign.center));
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
          BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: _freshCount.toDouble(), color: AppColors.success, width: 40, borderRadius: BorderRadius.circular(6))]),
          BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: _fadingCount.toDouble(), color: Colors.amber, width: 40, borderRadius: BorderRadius.circular(6))]),
          BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: _dormantCount.toDouble(), color: Colors.redAccent, width: 40, borderRadius: BorderRadius.circular(6))]),
        ],
      ),
    );
  }

  // 4. FORECAST CHART (FIXED: Full Height Hover)
  Widget _buildForecastBarChart() {
    final labels = ["Late", "Tmrw", "+2d", "+3d", "+4d", "+5d", "+6d"];
    int maxVal = _forecastCounts.reduce(max);
    if(maxVal == 0) maxVal = 5;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        maxY: maxVal.toDouble() + 2,
        barTouchData: BarTouchData(
          enabled: true,
          // 🚨 FIX: Allow touching the background bar to trigger tooltip!
          allowTouchBarBackDraw: true, 
          touchTooltipData: BarTouchTooltipData(
             tooltipBgColor: AppColors.cardColor,
             getTooltipItem: (group, groupIndex, rod, rodIndex) {
               return BarTooltipItem(
                 "${labels[group.x.toInt()]}\n${rod.toY.toInt()} words", 
                 const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)
               );
             }
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) {
            int idx = value.toInt();
            if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
            return Padding(padding: const EdgeInsets.only(top: 8), child: Text(labels[idx], style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 10)));
          })),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: false),
        barGroups: _forecastCounts.asMap().entries.map((entry) {
          Color barColor = entry.key == 0 ? Colors.redAccent : (entry.key == 1 ? Colors.amber : AppColors.primary);
          
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value.toDouble(),
                color: barColor,
                width: 24, // Wider bars for better visibility
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                // Background bar is now interactive!
                backDrawRodData: BackgroundBarChartRodData(
                  show: true, 
                  toY: maxVal.toDouble() + 2, 
                  color: AppColors.textSecondary.withOpacity(0.05)
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // 5. HEATMAP & HELPERS
  Widget _buildHeatmapDetailBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.textSecondary.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.textSecondary.withOpacity(0.1))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("SELECTED DATE", style: TextStyle(color: AppColors.textSecondary, fontSize: 10, letterSpacing: 1)),
              const SizedBox(height: 4),
              Text(DateFormat.yMMMMd().format(_selectedHeatmapDate), style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: _getHeatmapColor(_selectedHeatmapScore), borderRadius: BorderRadius.circular(20)),
            child: Text("$_selectedHeatmapScore interactions", style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

 Widget _buildHeatmapGraph() {
    return SizedBox(
      width: double.infinity,
      child: HeatMap(
        datasets: _heatmapData,
        colorMode: ColorMode.color, // Use specific colors for buckets
        scrollable: true,
        showText: false,
        // ✅ FIX: Thresholds updated to 200/400/800/1000
        // Gradient: Faint Primary -> Solid Primary -> Amber -> Bright Orange/Fire
        colorsets: {
          1: AppColors.primary.withOpacity(0.3),  // 1-199: Faint Green
          200: AppColors.primary.withOpacity(0.6),// 200-399: Medium Green
          400: AppColors.primary,                 // 400-799: Solid Green
          800: AppColors.accent,                  // 800-999: Amber/Orange
          1000: Colors.deepOrangeAccent,          // 1000+: Bright "Fire" Orange
        },
        onClick: (value) {
          setState(() {
            _selectedHeatmapDate = value;
            _selectedHeatmapScore = _heatmapData[value] ?? 0;
          });
        },
        // ✅ FIX: Very faint grey for empty days so they fade into the background
        defaultColor: Colors.white.withOpacity(0.05),
        textColor: AppColors.textPrimary,
        showColorTip: false,
        startDate: DateTime.now().subtract(const Duration(days: 80)),
        endDate: DateTime.now(),
        size: 28,
        margin: const EdgeInsets.all(2),
      ),
    );
  }
  
  Color _getHeatmapColor(int score) {
    // Exact match for the logic used in colorsets above
    if (score == 0) return Colors.white.withOpacity(0.05);
    if (score < 200) return AppColors.primary.withOpacity(0.3);
    if (score < 400) return AppColors.primary.withOpacity(0.6);
    if (score < 800) return AppColors.primary;
    if (score < 1000) return AppColors.accent;
    return Colors.deepOrangeAccent; // The bright orange color
  }

  Widget _buildHeader(String title) {
    return Padding(padding: const EdgeInsets.only(left: 4.0, bottom: 12.0), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)));
  }

  Widget _buildCard({double? height, required Widget child, EdgeInsets? padding}) {
    return Container(height: height, padding: padding ?? const EdgeInsets.all(24), decoration: BoxDecoration(color: AppColors.cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))]), child: child);
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 6), Text(label, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12))]);
  }
}