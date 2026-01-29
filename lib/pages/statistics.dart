import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:intl/intl.dart'; 
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'stats_provider.dart'; // 👈 IMPORT YOUR NEW PROVIDER

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  // 🔥 INTERACTIVE STATE (These are UI-only, so we keep them local)
  int _touchedIndex = -1;
  DateTime? _selectedHeatmapDate; 
  int _selectedHeatmapScore = 0;

  // 🔥 THEME COLORS
  final Color _cBlack = const Color(0xFF121212);     
  final Color _cCard  = const Color(0xFF1E1E1E);     
  final Color _cOrange = const Color(0xFFFF9800);    
  final Color _cDarkOrange = const Color(0xFFE65100);
  final Color _cGrey = const Color(0xFF424242);      

  @override
  Widget build(BuildContext context) {
    // 🧠 1. LISTEN TO THE BRAIN
    final statsAsync = ref.watch(statsProvider);

    return Scaffold(
      backgroundColor: _cBlack,
      appBar: AppBar(
        title: const Text("STATISTICS", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 22, letterSpacing: 1.2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      // 🧠 2. HANDLE STATES (Loading / Error / Data)
      body: statsAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: _cOrange)),
        error: (err, stack) => Center(child: Text("Error: $err", style: const TextStyle(color: Colors.red))),
        data: (stats) {
          
          // Calculate Totals for Summary
          int totalActive = stats.learning + stats.mastered;
          double retention = totalActive == 0 ? 0 : (stats.fresh / totalActive) * 100;

          // Default heatmap date to today if not selected
          final now = DateTime.now();
          final todayClean = DateTime(now.year, now.month, now.day);
          _selectedHeatmapDate ??= todayClean;
          // Note: If the user clicked a date, we respect that. If not, we show today's score from the DB
          if (_selectedHeatmapScore == 0) {
             _selectedHeatmapScore = stats.heatmapData[todayClean] ?? 0;
          }

          return RefreshIndicator(
            onRefresh: () async {
              // 🧠 3. PULL TO REFRESH
              return ref.refresh(statsProvider); 
            },
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
                       Expanded(child: _buildSummaryTile("DAYS", stats.heatmapData.length.toString(), Icons.local_fire_department)),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // 2. KNOWLEDGE DONUT (Pass 'stats')
                  _buildSectionTitle("PROGRESS"),
                  _buildDarkCard(
                    height: 320,
                    child: Column(
                      children: [
                         Expanded(child: _buildDonutChart(stats)),
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
                  
                  // 3. HISTORY CHART (Pass 'stats')
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle("VELOCITY"),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          "LAST ${stats.dateLabels.length} DAYS", 
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
                    height: 320,
                    padding: const EdgeInsets.fromLTRB(10, 16, 24, 10),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _buildLegendDot("Mastered", _cOrange),
                            const SizedBox(width: 16),
                            _buildLegendDot("Learning", _cDarkOrange),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Expanded(child: _buildHistoryChart(stats)),
                      ],
                    )
                  ),
                  const SizedBox(height: 30),

                  // 4. FUTURE LOAD
                  _buildSectionTitle("FORECAST"),
                  _buildDarkCard(
                    height: 320, 
                    padding: const EdgeInsets.only(top: 40, bottom: 10, left: 16, right: 16),
                    child: _buildForecastBarChart(stats)
                  ),
                  const SizedBox(height: 30),

                  // 5. MEMORY HEALTH
                  _buildSectionTitle("MEMORY STRENGTH"),
                  _buildDarkCard(
                    height: 300, 
                    padding: const EdgeInsets.only(top: 40, bottom: 20, left: 16, right: 16),
                    child: _buildFreshnessChart(stats)
                  ),
                  const SizedBox(height: 30),

                  // 6. HEATMAP
                  _buildSectionTitle("ACTIVITY"),
                  _buildDarkCard(
                    padding: const EdgeInsets.all(16), 
                    child: Column(
                      children: [
                        _buildHeatmapGraph(stats),
                        const Divider(color: Colors.white10, height: 20),
                        _buildHeatmapDetailRow(),
                      ],
                    )
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ================= UI WIDGETS =================

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 10.0),
      child: Text(
        title, 
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _cOrange, letterSpacing: 2.0)
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

  // ================= CHARTS (UPDATED TO TAKE 'STATS') =================

  Widget _buildHistoryChart(UserStats stats) {
    if (stats.learnedSpots.length < 2) return const Center(child: Text("Not enough data yet.", style: TextStyle(color: Colors.white38)));

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true, 
          drawVerticalLine: false, 
          horizontalInterval: stats.historyMaxY / 4 == 0 ? 1 : stats.historyMaxY / 4, 
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, 
              reservedSize: 28, 
              getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: const TextStyle(color: Colors.white38, fontSize: 10))
            )
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (stats.dateLabels.length / 5).ceil().toDouble(), 
              getTitlesWidget: (value, meta) {
                int index = value.toInt();
                if (index < 0 || index >= stats.dateLabels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    stats.dateLabels[index],
                    style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0, maxX: (stats.learnedSpots.length - 1).toDouble(),
        minY: 0, maxY: stats.historyMaxY,
        lineBarsData: [
          LineChartBarData(
            spots: stats.learningSpots,
            isCurved: true,
            color: _cDarkOrange.withOpacity(0.8),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true, 
              gradient: LinearGradient(
                colors: [_cDarkOrange.withOpacity(0.1), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            ),
          ),
          LineChartBarData(
            spots: stats.learnedSpots,
            isCurved: true,
            color: _cOrange,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
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
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: _cCard,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final bool isLearned = spot.barIndex == 1;
                return LineTooltipItem(
                  "${spot.y.toInt()}", 
                  TextStyle(color: isLearned ? _cOrange : _cDarkOrange, fontWeight: FontWeight.bold)
                );
              }).toList();
            }
          )
        ),
      ),
    );
  }

  Widget _buildDonutChart(UserStats stats) {
    double total = (stats.mastered + stats.learning + stats.newWords).toDouble();
    if (total == 0) total = 1; 

    String label = "TOTAL";
    String countStr = total.toInt().toString();
    Color textColor = Colors.white;

    if (_touchedIndex == 0) {
      label = "MASTERED";
      countStr = stats.mastered.toString();
      textColor = _cOrange;
    } else if (_touchedIndex == 1) {
      label = "LEARNING";
      countStr = stats.learning.toString();
      textColor = _cDarkOrange;
    } else if (_touchedIndex == 2) {
      label = "NEW";
      countStr = stats.newWords.toString();
      textColor = _cGrey;
    }

    return SizedBox(
      height: 220,
      child: Stack(
        children: [
          PieChart(
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
              sectionsSpace: 5,
              centerSpaceRadius: 70,
              sections: [
                _buildPieSection(0, stats.mastered.toDouble(), _cOrange, total),
                _buildPieSection(1, stats.learning.toDouble(), _cDarkOrange, total),
                _buildPieSection(2, stats.newWords.toDouble(), _cGrey, total),
              ],
            ),
          ),
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
                     key: ValueKey<String>(countStr),
                     style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: textColor)
                   ),
                 ),
                 AnimatedSwitcher(
                   duration: const Duration(milliseconds: 300),
                   child: Text(
                     label, 
                     key: ValueKey<String>(label),
                     style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.7), fontWeight: FontWeight.bold, letterSpacing: 2.0)
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
    final double radius = isTouched ? 25.0 : 16.0; 
    return PieChartSectionData(
      color: color.withOpacity(isTouched ? 1.0 : 0.8),
      value: value, 
      title: '', 
      radius: radius,
    );
  }

  Widget _buildFreshnessChart(UserStats stats) {
    int maxVal = max(stats.fresh, max(stats.fading, stats.dormant));
    if (maxVal == 0) maxVal = 10;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxVal * 1.3), 
        barTouchData: BarTouchData(
          enabled: false, 
          touchTooltipData: BarTouchTooltipData(
             tooltipBgColor: Colors.transparent, 
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
          _buildBar(0, stats.fresh, _cOrange),
          _buildBar(1, stats.fading, _cDarkOrange),
          _buildBar(2, stats.dormant, Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildForecastBarChart(UserStats stats) {
    final labels = ["Late", "Tmro", "+2d", "+3d", "+4d", "+5d", "+6d"];
    int maxVal = stats.forecast.reduce(max);
    if(maxVal == 0) maxVal = 5;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        maxY: maxVal.toDouble() + 5,
        barTouchData: BarTouchData(
          enabled: false,
          touchTooltipData: BarTouchTooltipData(
             tooltipBgColor: Colors.transparent,
             tooltipPadding: EdgeInsets.zero,
             tooltipMargin: 2,
             getTooltipItem: (group, groupIndex, rod, rodIndex) {
               return BarTooltipItem(
                 "${rod.toY.toInt()}", 
                 const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)
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
              reservedSize: 32, 
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
        barGroups: stats.forecast.asMap().entries.map((entry) {
          Color barColor = entry.key == 0 ? Colors.redAccent : _cOrange;
          return BarChartGroupData(
            x: entry.key,
            showingTooltipIndicators: entry.value > 0 ? [0] : [],
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
            Text(DateFormat.yMMMMd().format(_selectedHeatmapDate!).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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

  Widget _buildHeatmapGraph(UserStats stats) {
    return SizedBox(
      width: double.infinity,
      child: HeatMap(
        datasets: stats.heatmapData,
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
            _selectedHeatmapScore = stats.heatmapData[value] ?? 0;
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