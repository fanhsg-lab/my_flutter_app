import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'stats_provider.dart';
import '../responsive.dart';
import '../services/app_strings.dart';

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
    final r = Responsive(context);
    // 🧠 1. LISTEN TO THE BRAIN
    final statsAsync = ref.watch(statsProvider);

    return Scaffold(
      backgroundColor: _cBlack,
      // 🧠 2. HANDLE STATES (Loading / Error / Data)
      body: SafeArea(
        child: statsAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: _cOrange)),
        error: (err, stack) => Center(child: Text("${S.error}: $err", style: TextStyle(color: Colors.red, fontSize: r.fontSize(14)))),
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
              padding: EdgeInsets.symmetric(horizontal: r.spacing(16), vertical: r.spacing(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TITLE
                  Padding(
                    padding: EdgeInsets.only(top: r.spacing(8), bottom: r.spacing(12)),
                    child: Center(
                      child: Text(S.statistics.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: r.fontSize(18), letterSpacing: 1.5)),
                    ),
                  ),
                  // FILTER TOGGLE
                  _buildFilterToggle(r),
                  SizedBox(height: r.spacing(20)),

                  // 1. TOP SUMMARY ROW
                  Row(
                    children: [
                       Expanded(child: _buildSummaryTile(S.words, totalActive.toString(), Icons.book, r)),
                       SizedBox(width: r.spacing(12)),
                       Expanded(child: _buildSummaryTile(S.retention, "${retention.toInt()}%", Icons.bolt, r)),
                       SizedBox(width: r.spacing(12)),
                       Expanded(child: _buildSummaryTile(S.days, stats.heatmapData.length.toString(), Icons.local_fire_department, r)),
                    ],
                  ),
                  SizedBox(height: r.spacing(30)),

                  // 2. KNOWLEDGE DONUT (Pass 'stats')
                  _buildSectionTitle(S.progress, r),
                  _buildDarkCard(
                    r: r,
                    height: r.hp(40).clamp(280, 400),
                    child: Column(
                      children: [
                         Expanded(child: _buildDonutChart(stats, r)),
                         SizedBox(height: r.spacing(20)),
                         Row(
                           mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                           children: [
                             _buildLegendDot(S.mastered, _cOrange, r),
                             _buildLegendDot(S.learning, _cDarkOrange, r),
                             _buildLegendDot(S.newWord, _cGrey, r),
                           ],
                         ),
                         SizedBox(height: r.spacing(10)),
                      ],
                    ),
                  ),
                  SizedBox(height: r.spacing(30)),

                  // NEW: WEEKLY BREAKDOWN
                  _buildSectionTitle(S.thisWeek, r),
                  _buildDarkCard(
                    r: r,
                    height: r.hp(22).clamp(160, 220),
                    child: _buildWeeklySummary(stats, r),
                  ),
                  SizedBox(height: r.spacing(30)),

                  // 3. HISTORY CHART (Pass 'stats')
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle(S.velocity, r),
                      Padding(
                        padding: EdgeInsets.only(bottom: r.spacing(10)),
                        child: Text(
                          S.lastNDays(stats.dateLabels.length),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontWeight: FontWeight.bold,
                            fontSize: r.fontSize(10)
                          )
                        ),
                      ),
                    ],
                  ),
                  _buildDarkCard(
                    r: r,
                    height: r.chartHeight,
                    padding: EdgeInsets.fromLTRB(r.spacing(10), r.spacing(16), r.spacing(24), r.spacing(10)),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _buildLegendDot(S.mastered, _cOrange, r),
                            SizedBox(width: r.spacing(16)),
                            _buildLegendDot(S.learning, _cDarkOrange, r),
                          ],
                        ),
                        SizedBox(height: r.spacing(20)),
                        Expanded(child: _buildHistoryChart(stats, r)),
                      ],
                    )
                  ),
                  SizedBox(height: r.spacing(30)),

                  // 4. FUTURE LOAD
                  _buildSectionTitle(S.forecast, r),
                  _buildDarkCard(
                    r: r,
                    height: r.chartHeight,
                    padding: EdgeInsets.only(top: r.spacing(40), bottom: r.spacing(10), left: r.spacing(16), right: r.spacing(16)),
                    child: _buildForecastBarChart(stats, r)
                  ),
                  SizedBox(height: r.spacing(30)),

                  // 5. MEMORY HEALTH
                  _buildSectionTitle(S.memoryStrength, r),
                  _buildDarkCard(
                    r: r,
                    height: r.hp(35).clamp(250, 350),
                    padding: EdgeInsets.only(top: r.spacing(40), bottom: r.spacing(20), left: r.spacing(16), right: r.spacing(16)),
                    child: _buildFreshnessChart(stats, r)
                  ),
                  SizedBox(height: r.spacing(30)),

                  // 6. HEATMAP
                  _buildSectionTitle(S.activity, r),
                  _buildDarkCard(
                    r: r,
                    padding: EdgeInsets.all(r.spacing(16)),
                    child: Column(
                      children: [
                        _buildHeatmapGraph(stats, r),
                        Divider(color: Colors.white10, height: r.spacing(20)),
                        _buildHeatmapDetailRow(r),
                      ],
                    )
                  ),
                  SizedBox(height: r.spacing(40)),
                ],
              ),
            ),
          );
        },
      ),
      ),
    );
  }

  // ================= UI WIDGETS =================

  Widget _buildSectionTitle(String title, Responsive r) {
    return Padding(
      padding: EdgeInsets.only(left: r.spacing(4), bottom: r.spacing(10)),
      child: Text(
        title,
        style: TextStyle(fontSize: r.fontSize(14), fontWeight: FontWeight.bold, color: _cOrange, letterSpacing: 2.0)
      )
    );
  }

  Widget _buildDarkCard({double? height, required Widget child, EdgeInsets? padding, required Responsive r}) {
    return Container(
      height: height,
      padding: padding ?? EdgeInsets.all(r.spacing(20)),
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.circular(r.radius(16)),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: child
    );
  }

  Widget _buildFilterToggle(Responsive r) {
    final currentFilter = ref.watch(statsFilterProvider);

    return Container(
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.circular(r.radius(12)),
        border: Border.all(color: _cOrange.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          _buildFilterButton(
            label: S.thisBook,
            icon: Icons.menu_book,
            filter: StatsFilter.book,
            isSelected: currentFilter == StatsFilter.book,
            r: r,
          ),
          _buildFilterButton(
            label: S.thisTeacher,
            icon: Icons.person,
            filter: StatsFilter.teacher,
            isSelected: currentFilter == StatsFilter.teacher,
            r: r,
          ),
          _buildFilterButton(
            label: S.all,
            icon: Icons.public,
            filter: StatsFilter.all,
            isSelected: currentFilter == StatsFilter.all,
            r: r,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton({
    required String label,
    required IconData icon,
    required StatsFilter filter,
    required bool isSelected,
    required Responsive r,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          ref.read(statsFilterProvider.notifier).state = filter;
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: r.spacing(12)),
          decoration: BoxDecoration(
            color: isSelected ? _cOrange.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(r.radius(10)),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? _cOrange : Colors.grey,
                size: r.iconSize(18),
              ),
              SizedBox(height: r.spacing(4)),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? _cOrange : Colors.grey,
                  fontSize: r.fontSize(11),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryTile(String label, String value, IconData icon, Responsive r) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: r.spacing(16)),
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.circular(r.radius(12)),
        border: Border.all(color: _cOrange.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: _cOrange, size: r.iconSize(22)),
          SizedBox(height: r.spacing(8)),
          Text(value, style: TextStyle(fontSize: r.fontSize(20), fontWeight: FontWeight.bold, color: Colors.white)),
          SizedBox(height: r.spacing(4)),
          Text(label, style: TextStyle(fontSize: r.fontSize(10), fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.5))),
        ],
      ),
    );
  }

  Widget _buildLegendDot(String label, Color color, Responsive r) {
    return Row(children: [
      Container(width: r.scale(8), height: r.scale(8), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      SizedBox(width: r.spacing(6)),
      Text(label, style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: r.fontSize(12)))
    ]);
  }

  // ================= CHARTS (UPDATED TO TAKE 'STATS') =================

  Widget _buildHistoryChart(UserStats stats, Responsive r) {
    if (stats.learnedSpots.length < 2) return Center(child: Text(S.notEnoughData, style: TextStyle(color: Colors.white38, fontSize: r.fontSize(14))));

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: stats.historyMaxY / 4 == 0 ? 1 : stats.historyMaxY / 4,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: r.scale(28),
              getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: TextStyle(color: Colors.white38, fontSize: r.fontSize(10)))
            )
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: r.scale(22),
              interval: (stats.dateLabels.length / 5).ceil().toDouble(),
              getTitlesWidget: (value, meta) {
                int index = value.toInt();
                if (index < 0 || index >= stats.dateLabels.length) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.only(top: r.spacing(8)),
                  child: Text(
                    stats.dateLabels[index],
                    style: TextStyle(color: Colors.white38, fontSize: r.fontSize(10), fontWeight: FontWeight.bold),
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
            barWidth: r.scale(3),
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
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
            barWidth: r.scale(3),
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
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
                  TextStyle(color: isLearned ? _cOrange : _cDarkOrange, fontWeight: FontWeight.bold, fontSize: r.fontSize(12))
                );
              }).toList();
            }
          )
        ),
      ),
    );
  }

  Widget _buildDonutChart(UserStats stats, Responsive r) {
    double total = (stats.mastered + stats.learning + stats.newWords).toDouble();
    if (total == 0) total = 1;

    String label = S.totalUpper;
    String countStr = total.toInt().toString();
    Color textColor = Colors.white;

    if (_touchedIndex == 0) {
      label = S.masteredUpper;
      countStr = stats.mastered.toString();
      textColor = _cOrange;
    } else if (_touchedIndex == 1) {
      label = S.learningUpper;
      countStr = stats.learning.toString();
      textColor = _cDarkOrange;
    } else if (_touchedIndex == 2) {
      label = S.newUpper;
      countStr = stats.newWords.toString();
      textColor = _cGrey;
    }

    return SizedBox(
      height: r.donutHeight,
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
              sectionsSpace: r.scale(5),
              centerSpaceRadius: r.scale(70),
              sections: [
                _buildPieSection(0, stats.mastered.toDouble(), _cOrange, total, r),
                _buildPieSection(1, stats.learning.toDouble(), _cDarkOrange, total, r),
                _buildPieSection(2, stats.newWords.toDouble(), _cGrey, total, r),
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
                     style: TextStyle(fontSize: r.fontSize(36), fontWeight: FontWeight.w900, color: textColor)
                   ),
                 ),
                 AnimatedSwitcher(
                   duration: const Duration(milliseconds: 300),
                   child: Text(
                     label,
                     key: ValueKey<String>(label),
                     style: TextStyle(fontSize: r.fontSize(12), color: textColor.withOpacity(0.7), fontWeight: FontWeight.bold, letterSpacing: 2.0)
                   ),
                 ),
               ],
             )
          )
        ],
      ),
    );
  }

  PieChartSectionData _buildPieSection(int index, double value, Color color, double total, Responsive r) {
    final isTouched = index == _touchedIndex;
    final double radius = isTouched ? r.scale(25) : r.scale(16);
    return PieChartSectionData(
      color: color.withOpacity(isTouched ? 1.0 : 0.8),
      value: value,
      title: '',
      radius: radius,
    );
  }

  Widget _buildFreshnessChart(UserStats stats, Responsive r) {
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
             tooltipMargin: r.scale(2),
             getTooltipItem: (group, groupIndex, rod, rodIndex) {
               return BarTooltipItem(
                 rod.toY.toInt().toString(),
                 TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: r.fontSize(16)),
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
                final style = TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: r.fontSize(10));
                String text;
                switch (value.toInt()) {
                  case 0: text = S.recentWk; break;
                  case 1: text = S.slippingMo; break;
                  case 2: text = S.lostMo; break;
                  default: text = '';
                }
                return Padding(padding: EdgeInsets.only(top: r.spacing(10)), child: Text(text, style: style, textAlign: TextAlign.center));
              },
              reservedSize: r.scale(40),
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: [
          _buildBar(0, stats.fresh, _cOrange, r),
          _buildBar(1, stats.fading, _cDarkOrange, r),
          _buildBar(2, stats.dormant, Colors.redAccent, r),
        ],
      ),
    );
  }

  Widget _buildForecastBarChart(UserStats stats, Responsive r) {
    final labels = S.forecastLabels;
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
             tooltipMargin: r.scale(2),
             getTooltipItem: (group, groupIndex, rod, rodIndex) {
               return BarTooltipItem(
                 "${rod.toY.toInt()}",
                 TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: r.fontSize(14))
               );
             }
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: r.scale(32),
              getTitlesWidget: (value, meta) {
                int idx = value.toInt();
                if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.only(top: r.spacing(12)),
                  child: Text(labels[idx], style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: r.fontSize(10)))
                );
              }
            )
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        barGroups: stats.forecast.asMap().entries.map((entry) {
          Color barColor = entry.key == 0 ? Colors.redAccent : _cOrange;
          return BarChartGroupData(
            x: entry.key,
            showingTooltipIndicators: entry.value > 0 ? [0] : [],
            barRods: [
              BarChartRodData(
                toY: entry.value.toDouble(),
                color: barColor,
                width: r.scale(14),
                borderRadius: BorderRadius.circular(r.radius(2)),
                backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxVal.toDouble() + 5, color: Colors.white.withOpacity(0.05)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  BarChartGroupData _buildBar(int x, int value, Color color, Responsive r) {
    return BarChartGroupData(
      x: x,
      showingTooltipIndicators: value > 0 ? [0] : [],
      barRods: [
        BarChartRodData(
          toY: value.toDouble(),
          color: color,
          width: r.scale(25),
          borderRadius: BorderRadius.vertical(top: Radius.circular(r.radius(4))),
          backDrawRodData: BackgroundBarChartRodData(show: true, toY: null, color: Colors.white.withOpacity(0.05))
        )
      ]
    );
  }

  Widget _buildHeatmapDetailRow(Responsive r) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat.yMMMMd().format(_selectedHeatmapDate!).toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: r.fontSize(12))),
            SizedBox(height: r.spacing(2)),
            Text(S.selectedDate, style: TextStyle(color: Colors.white38, fontSize: r.fontSize(10))),
          ],
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: r.spacing(16), vertical: r.spacing(8)),
          decoration: BoxDecoration(color: _cOrange, borderRadius: BorderRadius.circular(r.radius(8))),
          child: Text("$_selectedHeatmapScore XP", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: r.fontSize(14))),
        )
      ],
    );
  }

  Widget _buildHeatmapGraph(UserStats stats, Responsive r) {
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
        size: r.heatmapSize,
        margin: EdgeInsets.all(r.spacing(2)),
      ),
    );
  }

  Widget _buildWeeklySummary(UserStats stats, Responsive r) {
    // Rolling last-7-days window (today is the rightmost bar)
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dayNames = S.dayNames;

    int weeklyWords = 0;
    int activeDays = 0;
    int bestDay = 0;

    for (int i = 0; i < 7; i++) {
      final day = today.subtract(Duration(days: 6 - i));
      final count = stats.heatmapData[day] ?? 0;
      if (count > 0) {
        weeklyWords += count;
        activeDays++;
        if (count > bestDay) bestDay = count;
      }
    }

    final dailyAvg = activeDays > 0 ? (weeklyWords / activeDays).round() : 0;

    return Column(
      children: [
        // Mini bar chart for last 7 days
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (index) {
              final day = today.subtract(Duration(days: 6 - index));
              final count = stats.heatmapData[day] ?? 0;
              final isToday = index == 6; // rightmost bar is always today
              final maxHeight = bestDay > 0 ? bestDay : 1;
              final heightPercent = count / maxHeight;
              final label = dayNames[day.weekday - 1]; // Mon=1 → index 0

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: r.spacing(2)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Bar
                      Container(
                        height: r.scale(50) * heightPercent,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: isToday
                                ? [_cOrange, _cOrange.withOpacity(0.6)]
                                : [_cDarkOrange.withOpacity(0.8), _cDarkOrange.withOpacity(0.4)],
                          ),
                          borderRadius: BorderRadius.circular(r.radius(4)),
                          border: isToday ? Border.all(color: _cOrange, width: 2) : null,
                        ),
                      ),
                      SizedBox(height: r.spacing(8)),
                      // Day label (e.g. "Mon", "Tue", today highlighted)
                      Text(
                        isToday ? S.today : label,
                        style: TextStyle(
                          color: isToday ? _cOrange : Colors.white54,
                          fontSize: r.fontSize(9),
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        SizedBox(height: r.spacing(16)),
        // Stats row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildMiniStat("$weeklyWords", S.total, r),
            Container(width: 1, height: r.scale(20), color: Colors.white10),
            _buildMiniStat("$activeDays/7", S.days, r),
            Container(width: 1, height: r.scale(20), color: Colors.white10),
            _buildMiniStat("$dailyAvg", S.avgDay, r),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniStat(String value, String label, Responsive r) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: _cOrange, fontSize: r.fontSize(18), fontWeight: FontWeight.bold)),
        SizedBox(height: r.spacing(2)),
        Text(label, style: TextStyle(color: Colors.white38, fontSize: r.fontSize(9), fontWeight: FontWeight.bold)),
      ],
    );
  }
}