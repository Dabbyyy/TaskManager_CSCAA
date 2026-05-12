import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class CalendarMonitor extends StatefulWidget {
  final bool isAdmin;
  const CalendarMonitor({super.key, required this.isAdmin});
  @override
  State<CalendarMonitor> createState() => _CalendarMonitorState();
}

class _CalendarMonitorState extends State<CalendarMonitor> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();

  Color getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return const Color(0xFF2196F3);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = FirebaseAuth.instance.currentUser?.email;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, userSnap) {
        final Map<String, String> userNames = {
          for (var d in userSnap.data?.docs ?? []) d.id: d['fullName'] ?? d.id
        };

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('tasks')
              .where('isDone', isEqualTo: false)
              .snapshots(),
          builder: (ctx, snap) {
            final allTasks = snap.data?.docs ?? [];

            List<QueryDocumentSnapshot> getEvents(DateTime day) {
              return allTasks.where((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final deadline = (d['deadline'] as Timestamp?)?.toDate();
                return deadline != null &&
                    isSameDay(deadline, day) &&
                    (widget.isAdmin ||
                        (d['assignedTo'] as List).contains(userEmail));
              }).map((e) => e as QueryDocumentSnapshot).toList();
            }

            return Column(
              children: [
                Expanded(
                  child: TableCalendar(
                    focusedDay: _focusedDay,
                    firstDay: DateTime.utc(2025),
                    lastDay: DateTime.utc(2030),
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    eventLoader: getEvents,
                    onDaySelected: (sel, foc) => setState(() {
                      _selectedDay = sel;
                      _focusedDay = foc;
                    }),
                    rowHeight: 90, // Increased row height to fit task labels
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: false,
                      titleTextStyle: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                      leftChevronIcon: const Icon(Icons.chevron_left, size: 24),
                      rightChevronIcon: const Icon(Icons.chevron_right, size: 24),
                      headerPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
                    ),
                    daysOfWeekStyle: const DaysOfWeekStyle(
                      weekdayStyle: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.black54),
                      weekendStyle: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.black54),
                    ),
                    calendarStyle: const CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: Color(0xFFFDE8E8), // Light highlight for today
                        shape: BoxShape.rectangle,
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      selectedDecoration: BoxDecoration(
                        color: Color(0xFFF3F4F6), // Light highlight for selected
                        shape: BoxShape.rectangle,
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      outsideDaysVisible: true,
                    ),
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (context, day, focusedDay) =>
                          _buildDayCell(day, getEvents(day)),
                      todayBuilder: (context, day, focusedDay) =>
                          _buildDayCell(day, getEvents(day), isToday: true),
                      selectedBuilder: (context, day, focusedDay) =>
                          _buildDayCell(day, getEvents(day), isSelected: true),
                      outsideBuilder: (context, day, focusedDay) =>
                          _buildDayCell(day, [], isOutside: true),
                      markerBuilder: (context, day, events) =>
                          const SizedBox(), // Disable default markers
                    ),
                  ),
                ),
                const Divider(height: 1),
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Row(
                    children: [
                      const Text("Selected Day: ",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(DateFormat('MMMM d, yyyy')
                          .format(_selectedDay ?? _focusedDay)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: getEvents(_selectedDay ?? _focusedDay).map((t) {
                      final data = t.data() as Map<String, dynamic>;
                      final emails = List<String>.from(data['assignedTo'] ?? []);
                      final names =
                          emails.map((e) => userNames[e] ?? e).join(", ");
                      final priority = data['priority'] ?? "Medium";
                      final color = getPriorityColor(priority);

                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Text(data['title'],
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("Assigned: $names\nPriority: $priority",
                              style: const TextStyle(fontSize: 12)),
                          isThreeLine: true,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDayCell(DateTime day, List<QueryDocumentSnapshot> events,
      {bool isToday = false, bool isSelected = false, bool isOutside = false}) {
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFFF3F4F6)
            : (isToday ? const Color(0xFFFDE8E8) : Colors.white),
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.normal,
                color: isOutside ? Colors.grey : (isToday ? Colors.red : Colors.black87),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                children: events.take(3).map((e) {
                  final data = e.data() as Map<String, dynamic>;
                  final priority = data['priority'] ?? "Medium";
                  final color = getPriorityColor(priority);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            data['title'],
                            style: TextStyle(
                              fontSize: 8,
                              color: color.withOpacity(0.8),
                              fontWeight: FontWeight.bold,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          if (events.length > 3)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                '+${events.length - 3} more',
                style: const TextStyle(fontSize: 8, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}
