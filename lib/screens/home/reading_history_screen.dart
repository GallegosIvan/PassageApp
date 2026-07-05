import 'package:flutter/material.dart';
import '../../services/home_service.dart';

class ReadingHistoryScreen extends StatefulWidget {
  const ReadingHistoryScreen({super.key});

  @override
  State<ReadingHistoryScreen> createState() => _ReadingHistoryScreenState();
}

class _ReadingHistoryScreenState extends State<ReadingHistoryScreen> {
  final _homeService = HomeService();
  Set<String> _readDates = {};
  bool _isLoading = true;
  late DateTime _visibleMonth;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final raw = await _homeService.getAllDaysRead();
    if (mounted) {
      setState(() {
        _readDates = raw.toSet();
        _isLoading = false;
      });
    }
  }

  bool _wasReadOn(DateTime date) {
    final key = date.toIso8601String().substring(0, 10);
    return _readDates.contains(key);
  }

  void _previousMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    if (next.isAfter(DateTime(now.year, now.month, 1))) return;
    setState(() => _visibleMonth = next);
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _visibleMonth.year == now.year && _visibleMonth.month == now.month;
  }

  List<DateTime?> _buildMonthCells() {
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final leadingBlanks = _visibleMonth.weekday % 7;
    final cells = <DateTime?>[];
    cells.addAll(List.filled(leadingBlanks, null));
    for (int day = 1; day <= daysInMonth; day++) {
      cells.add(DateTime(_visibleMonth.year, _visibleMonth.month, day));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  int _countReadDaysInMonth() {
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int count = 0;
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
      if (!date.isAfter(today) && _wasReadOn(date)) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final cells = _buildMonthCells();
    final readCount = _countReadDaysInMonth();
    final numWeeks = (cells.length / 7).ceil();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Reading History',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    // ── MONTH NAVIGATOR ───────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
                            onPressed: _previousMonth,
                          ),
                          Column(
                            children: [
                              Text(
                                '${_monthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$readCount ${readCount == 1 ? "day" : "days"} read',
                                style: const TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(Icons.chevron_right,
                                color: _isCurrentMonth ? Colors.white24 : Colors.white, size: 28),
                            onPressed: _isCurrentMonth ? null : _nextMonth,
                          ),
                        ],
                      ),
                    ),

                    // ── WEEKDAY HEADER ─────────────────────────
                    Row(
                      children: _dayLabels
                          .map((label) => Expanded(
                                child: Center(
                                  child: Text(label,
                                      style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ))
                          .toList(),
                    ),

                    const SizedBox(height: 8),

                    // ── CALENDAR GRID ──────────────────────────
                    // Each week row is an Expanded inside the
                    // parent Column so all rows share the full
                    // remaining height equally — no dead space
                    // below, no scrolling needed.
                    Expanded(
                      child: Column(
                        children: List.generate(numWeeks, (weekIndex) {
                          final weekCells = cells.sublist(weekIndex * 7, weekIndex * 7 + 7);
                          return Expanded(
                            child: Row(
                              children: weekCells.map((date) {
                                if (date == null) {
                                  return const Expanded(child: SizedBox());
                                }

                                final now = DateTime.now();
                                final isToday = date.year == now.year &&
                                    date.month == now.month &&
                                    date.day == now.day;
                                final isFuture = date.isAfter(
                                    DateTime(now.year, now.month, now.day));
                                final wasRead = !isFuture && _wasReadOn(date);

                                return Expanded(
                                  child: Center(
                                    child: AspectRatio(
                                      aspectRatio: 1,
                                      child: FractionallySizedBox(
                                        widthFactor: 0.82,
                                        heightFactor: 0.82,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: wasRead
                                                ? Colors.white
                                                : isToday
                                                    ? Colors.white.withOpacity(0.3)
                                                    : Colors.transparent,
                                            shape: BoxShape.circle,
                                            border: isToday
                                                ? Border.all(
                                                    color: Colors.white, width: 1.5)
                                                : null,
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${date.day}',
                                            style: TextStyle(
                                              color: wasRead
                                                  ? Colors.black
                                                  : isFuture
                                                      ? Colors.white24
                                                      : Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        }),
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }
}