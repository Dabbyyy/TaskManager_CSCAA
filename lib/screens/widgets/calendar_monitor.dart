import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CalendarMonitor extends StatefulWidget {
  final bool isAdmin;
  const CalendarMonitor({super.key, required this.isAdmin});
  @override
  State<CalendarMonitor> createState() => _CalendarMonitorState();
}

class _CalendarMonitorState extends State<CalendarMonitor> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();

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

            List<dynamic> getEvents(DateTime day) => allTasks.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final deadline = (d['deadline'] as Timestamp?)?.toDate();
                  return deadline != null &&
                      isSameDay(deadline, day) &&
                      (widget.isAdmin ||
                          (d['assignedTo'] as List).contains(userEmail));
                }).toList();

            return Column(children: [
              TableCalendar(
                focusedDay: _focusedDay,
                firstDay: DateTime.utc(2025),
                lastDay: DateTime.utc(2030),
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                eventLoader: getEvents,
                onDaySelected: (sel, foc) => setState(() {
                  _selectedDay = sel;
                  _focusedDay = foc;
                }),
                calendarStyle: const CalendarStyle(
                  todayDecoration: BoxDecoration(
                      color: Color(0x66700202), shape: BoxShape.circle),
                  selectedDecoration: BoxDecoration(
                      color: Color(0xFF700202), shape: BoxShape.circle),
                  markerDecoration: BoxDecoration(
                      color: Color(0xFF700202), shape: BoxShape.circle),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                    children: getEvents(_selectedDay ?? _focusedDay).map((t) {
                  final emails = List<String>.from(t['assignedTo'] ?? []);
                  final names = emails.map((e) => userNames[e] ?? e).join(", ");
                  return ListTile(
                    leading: const Icon(Icons.circle,
                        size: 12, color: Color(0xFF700202)),
                    title: Text(t['title']),
                    subtitle: Text("Assigned: $names"),
                  );
                }).toList()),
              ),
            ]);
          },
        );
      },
    );
  }
}
