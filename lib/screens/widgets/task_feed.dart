import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'custom_dialogs.dart';
import 'task_modal.dart';
import '../../services/notification_service.dart';

class TaskFeed extends StatefulWidget {
  final bool isArchive;
  final bool isAdmin;
  final String? subAdminEmail;

  const TaskFeed({
    super.key,
    required this.isArchive,
    required this.isAdmin,
    this.subAdminEmail,
  });

  @override
  State<TaskFeed> createState() => _TaskFeedState();
}

class _TaskFeedState extends State<TaskFeed> {

  String selectedOfficeFilter = 'All';
  Set<String> collapsedEventIds = {};

  Color getPriorityColor(String p) {
    if (p == "High") return Colors.red.shade700;
    if (p == "Medium") return Colors.orange.shade800;
    return Colors.green.shade700;
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = FirebaseAuth.instance.currentUser?.email;

    Query query = FirebaseFirestore.instance
        .collection('tasks')
        .where('isAccepted', isEqualTo: widget.isArchive);

    if (widget.isArchive) {
      if (widget.subAdminEmail != null) {
        query = query.where('createdBy', isEqualTo: widget.subAdminEmail);
      } else if (!widget.isAdmin) {
        query = query.where('assignedTo', arrayContains: userEmail);
      }
    } else {
      if (!widget.isAdmin && widget.subAdminEmail == null) {
        query = query.where('assignedTo', arrayContains: userEmail);
      }
    }

    final bool canDelete = widget.isAdmin || widget.subAdminEmail != null;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, userSnap) {
        final Map<String, dynamic> usersMap = {
          for (var d in userSnap.data?.docs ?? []) d.id: d.data()
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: ['All', 'SOCCOM', 'Alumni'].map((filter) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(filter, style: TextStyle(
                        color: selectedOfficeFilter == filter ? Colors.white : Colors.black87,
                      )),
                      selected: selectedOfficeFilter == filter,
                      selectedColor: const Color(0xFF3F598F),
                      onSelected: (bool selected) {
                        setState(() {
                          if (selected) selectedOfficeFilter = filter;
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),


            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: query.snapshots(),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: Color(0xFF3F598F)));
                  }

                  if (!snap.hasData) {
                    return const SizedBox.shrink();
                  }

                  final allDocs = snap.data!.docs;
                  final filteredDocs = allDocs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    if (selectedOfficeFilter != 'All') {
                      final office = data['office'] ?? 'SOCCOM';
                      return office == selectedOfficeFilter;
                    }
                    return true;
                  }).toList();

                  // Sort from latest to oldest based on 'createdAt'
                  filteredDocs.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final aTime = aData['createdAt'] as Timestamp?;
                    final bTime = bData['createdAt'] as Timestamp?;
                    if (aTime == null && bTime == null) return 0;
                    if (aTime == null) return 1;
                    if (bTime == null) return -1;
                    return bTime.compareTo(aTime);
                  });

                  if (filteredDocs.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: () async => await Future.delayed(const Duration(seconds: 1)),
                      child: ListView(
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.assignment_turned_in_outlined,
                                    size: 60, color: Colors.grey[300]),
                                const SizedBox(height: 10),
                                Text(widget.isArchive ? "No archived tasks." : "No active tasks.",
                                    style:
                                        TextStyle(color: Colors.grey[600], fontSize: 16)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async => await Future.delayed(const Duration(seconds: 1)),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final d = filteredDocs[index];
                      final data = d.data() as Map<String, dynamic>;


                      return Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            InkWell(
                              onTap: () {
                                setState(() {
                                  if (collapsedEventIds.contains(d.id)) {
                                    collapsedEventIds.remove(d.id);
                                  } else {
                                    collapsedEventIds.add(d.id);
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(data['title'] ?? "Untitled Event",
                                          style: const TextStyle(fontSize: 24, color: Colors.black87)),
                                    ),
                                    Icon(collapsedEventIds.contains(d.id) ? Icons.expand_more : Icons.expand_less, color: Colors.grey),
                                    const SizedBox(width: 8),
                                    if (canDelete)
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert, color: Colors.grey),
                                        onSelected: (val) async {
                                          if (val == 'rename') {
                                            TaskModal.show(context, existingTask: d, userRole: widget.isAdmin ? 'admin' : 'sub-admin');
                                          } else if (val == 'add') {
                                            final String eventOffice = data['office'] ?? 'SOCCOM';
                                            final simplifiedStaffMap = <String, String>{};
                                            usersMap.forEach((email, uData) {
                                              if (uData['office'] == eventOffice && uData['role'] != 'admin') {
                                                simplifiedStaffMap[email] = uData['fullName'] ?? email;
                                              }
                                            });
                                            TaskModal.showAddTaskDialog(context, simplifiedStaffMap, (newTask) async {
                                              final updatedSubTasks = List<Map<String, dynamic>>.from(data['subTasks'] ?? []);
                                              updatedSubTasks.add(newTask);
                                              
                                              List<String> eventAssigned = List<String>.from(data['assignedTo'] ?? []);
                                              for (String e in newTask['assignedTo']) {
                                                if (!eventAssigned.contains(e)) eventAssigned.add(e);
                                              }
                                              await d.reference.update({'subTasks': updatedSubTasks, 'assignedTo': eventAssigned});
                                            });
                                          } else if (val == 'delete') {
                                            final confirmed = await CustomDialogs.showConfirmDialog(context: context, title: "Delete Event", message: "Are you sure you want to delete this event?");
                                            if (confirmed == true) { d.reference.delete(); }
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(value: 'rename', child: Text("Rename Event")),
                                          const PopupMenuItem(value: 'add', child: Text("Add Task")),
                                          const PopupMenuItem(value: 'delete', child: Text("Delete Event", style: TextStyle(color: Colors.red))),
                                        ],
                                      )
                                  ],
                                ),
                              ),
                            ),
                            Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
                            if (!collapsedEventIds.contains(d.id)) ...[
                              if (data.containsKey('subTasks') && (data['subTasks'] as List).isNotEmpty)
                                ...List.generate((data['subTasks'] as List).length, (subIndex) {
                                final subTask = data['subTasks'][subIndex] as Map<String, dynamic>;
                                final bool taskIsDone = subTask['isDone'] ?? false;
                                final Timestamp? deadlineTs = subTask['deadline'] as Timestamp?;
                                final DateTime? deadline = deadlineTs?.toDate();
                                final DateTime now = DateTime.now();

                                String statusLabel = "Assigned";
                                Color statusColor = Colors.grey.shade600;

                                if (taskIsDone) {
                                  statusLabel = "Turned in";
                                  statusColor = Colors.green.shade700;
                                } else if (deadline != null) {
                                  if (deadline.isBefore(now)) {
                                    statusLabel = "Missing";
                                    statusColor = Colors.red.shade700;
                                  } else if (deadline.day == now.day && deadline.month == now.month && deadline.year == now.year) {
                                    statusLabel = "Due today";
                                    statusColor = Colors.orange.shade800;
                                  }
                                }
                                
                                final subAssignedEmails = List<String>.from(subTask['assignedTo'] ?? []);
                                final subAssignedNames = subAssignedEmails
                                    .map((e) => usersMap[e]?['fullName'] ?? e)
                                    .join(", ");

                                return Column(
                                  children: [
                                    ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      onTap: () {
                                        _showSubmissionSheet(context, d, data, usersMap, subIndex: subIndex);
                                      },
                                      leading: CircleAvatar(
                                        radius: 20,
                                        backgroundColor: taskIsDone ? Colors.grey.shade400 : const Color(0xFF3F598F),
                                        child: const Icon(Icons.assignment, color: Colors.white, size: 20),
                                      ),
                                      title: Text(subTask['task'] ?? "Untitled Task",
                                          style: TextStyle(
                                            fontSize: 15, 
                                            fontWeight: FontWeight.w500,
                                            decoration: taskIsDone ? TextDecoration.lineThrough : null,
                                            color: taskIsDone ? Colors.grey : Colors.black87
                                          )),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                                widget.isAdmin || widget.subAdminEmail != null
                                                    ? "Assigned: $subAssignedNames\nStatus: ${data['status'] ?? (taskIsDone ? 'Submitted' : 'Pending')}"
                                                    : "Status: ${data['status'] ?? (taskIsDone ? 'Submitted' : 'Pending')}",
                                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                            const SizedBox(height: 3),
                                            Text(
                                              subTask['deadline'] != null
                                                  ? "Due ${DateFormat('MMM d, y, h:mm a').format((subTask['deadline'] as Timestamp).toDate())}"
                                                  : "No due date",
                                              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(statusLabel, 
                                            style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.w500)),
                                          const SizedBox(width: 8),
                                          if (canDelete && !taskIsDone)
                                            IconButton(
                                              tooltip: "Remind assigned staff",
                                              onPressed: () => _sendReminder(
                                                context,
                                                subTask,
                                                data['title'] ?? 'a task',
                                                usersMap,
                                              ),
                                              icon: const Icon(Icons.notifications_active_outlined, size: 20, color: Color(0xFF700202)),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                            ),
                                          if (canDelete)
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert, color: Colors.grey),
                                              onSelected: (val) async {
                                                if (val == 'edit') {
                                                  final simplifiedStaffMap = usersMap.map((key, value) => MapEntry(key, value['fullName'].toString()));
                                                  TaskModal.showAddTaskDialog(context, simplifiedStaffMap, (updatedTask) async {
                                                    final updatedSubTasks = List<Map<String, dynamic>>.from(data['subTasks'] ?? []);
                                                    updatedSubTasks[subIndex] = updatedTask;
                                                    
                                                    List<String> eventAssigned = List<String>.from(data['assignedTo'] ?? []);
                                                    for (String e in updatedTask['assignedTo']) {
                                                      if (!eventAssigned.contains(e)) eventAssigned.add(e);
                                                    }
                                                    await d.reference.update({'subTasks': updatedSubTasks, 'assignedTo': eventAssigned});
                                                  }, existingTask: subTask);
                                                } else if (val == 'delete') {
                                                  final confirmed = await CustomDialogs.showConfirmDialog(context: context, title: "Delete Task", message: "Are you sure you want to delete this specific task?");
                                                  if (confirmed == true) {
                                                    final updatedSubTasks = List<Map<String, dynamic>>.from(data['subTasks'] ?? []);
                                                    updatedSubTasks.removeAt(subIndex);
                                                    await d.reference.update({'subTasks': updatedSubTasks});
                                                  }
                                                }
                                              },
                                              itemBuilder: (ctx) => [
                                                const PopupMenuItem(value: 'edit', child: Text("Edit Task")),
                                                const PopupMenuItem(value: 'delete', child: Text("Delete Task", style: TextStyle(color: Colors.red))),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                    Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                                  ],
                                );
                              })
                              else
                                const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text("No tasks in this event.",
                                      style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                                ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSubmissionSheet(
      BuildContext context, DocumentSnapshot doc, Map<String, dynamic> data, Map<String, dynamic> usersMap, {int? subIndex}) {
    final subTasks = List<Map<String, dynamic>>.from(data['subTasks'] ?? []);
    final currentSubTask = (subIndex != null && subIndex < subTasks.length) ? subTasks[subIndex] : null;

    final linkController =
        TextEditingController(text: data['submissionLink'] ?? "");
    
    // Check if this specific sub-task (or the whole event) is done
    final bool taskIsDone = currentSubTask != null ? (currentSubTask['isDone'] ?? false) : (data['isDone'] ?? false);
    
    final bool isAccepted = data['isAccepted'] ?? false;
    final String? userEmail = FirebaseAuth.instance.currentUser?.email;
    final bool isCreator = data['createdBy'] == userEmail;
    final bool canReview = widget.isAdmin || isCreator;
    final String displayTitle = currentSubTask != null ? (currentSubTask['task'] ?? data['title']) : data['title'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 12,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10)))),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Text(displayTitle,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold))),
                    if (isAccepted)
                      const Chip(
                          label: Text("ACCEPTED",
                              style:
                                  TextStyle(color: Colors.white, fontSize: 10)),
                          backgroundColor: Colors.blue)
                    else if (taskIsDone)
                      const Chip(
                          label: Text("SUBMITTED",
                              style:
                                  TextStyle(color: Colors.white, fontSize: 10)),
                          backgroundColor: Colors.green),
                    if (canReview && !taskIsDone)
                      IconButton(
                        icon: const Icon(Icons.edit, color: Color(0xFF3F598F)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          TaskModal.show(context, existingTask: doc, userRole: widget.isAdmin ? 'admin' : 'sub-admin');
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(data['instructions'] ?? "No instructions provided.",
                    style:
                        const TextStyle(fontSize: 15, color: Colors.black87)),
                const Divider(height: 30),
                if (!canReview && !taskIsDone) ...[
                  const Text("SUBMIT YOUR WORK",
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF3F598F))),
                  const SizedBox(height: 15),
                  TextField(
                    controller: linkController,
                    decoration: const InputDecoration(
                        hintText: "Paste link (Drive, GitHub, etc.)",
                        prefixIcon: Icon(Icons.link),
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  const Text("Please provide a link to your submitted work (Google Drive, Github, etc.)", 
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 10),
                  const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3F598F),
                          minimumSize: const Size(double.infinity, 55)),
                      onPressed: isAccepted ? null : () async {
                        final confirmed = await CustomDialogs.showConfirmDialog(
                          context: context,
                          title: "Submit Task",
                          message: "Confirm submission of work?");
                      if (confirmed == true) {
                        try {
                          final updatedSubTasks = List<Map<String, dynamic>>.from(data['subTasks'] ?? []);
                          
                          if (subIndex != null && subIndex < updatedSubTasks.length) {
                            updatedSubTasks[subIndex]['isDone'] = true;
                          } else {
                            // If no subIndex provided, mark all (fallback)
                            for (var i = 0; i < updatedSubTasks.length; i++) {
                              updatedSubTasks[i]['isDone'] = true;
                            }
                          }

                          // Check if ALL sub-tasks are done
                          bool allDone = updatedSubTasks.every((st) => st['isDone'] == true);

                          await doc.reference.update({
                            'isDone': allDone,
                            'isAccepted': allDone, // Auto-archive if all tasks are done
                            'status': allDone ? 'Submitted (Archived)' : 'Pending',
                            'submissionLink': linkController.text.trim(),
                            'submittedAt': FieldValue.serverTimestamp(),
                            'submittedBy':
                                FirebaseAuth.instance.currentUser?.email,
                            'subTasks': updatedSubTasks,
                          });

                          // Notify the creator (Admin/Sub-admin) that work has been submitted
                          final String? creatorEmail = data['createdBy'];
                          if (creatorEmail != null) {
                            await FirebaseFirestore.instance.collection('notifications').add({
                              'to': creatorEmail,
                              'title': 'Task Submitted',
                              'taskName': displayTitle,
                              'eventTitle': data['title'] ?? '',
                              'isRead': false,
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                            
                            // 🔥 Send real push notification via FCM
                            NotificationService.sendPushNotification(
                              toEmail: creatorEmail,
                              title: 'Task Submitted',
                              body: 'A task "$displayTitle" was submitted for review.',
                            );
                          }

                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                           if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Submission failed: $e")));
                           }
                        }
                      }
                    },
                    child: Text(isAccepted ? "SUBMITTED & ACCEPTED" : "MARK AS DONE",
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
                if (taskIsDone) ...[
                  const Text("SUBMITTED DATA",
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey)),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            "Link: ${data['submissionLink']?.isEmpty ?? true ? 'None' : data['submissionLink']}",
                            style: const TextStyle(
                                color: Colors.blue, fontSize: 13)),
                        const SizedBox(height: 8),
                        Text(
                            "File: ${data['submittedFileName']?.isEmpty ?? true ? 'None' : data['submittedFileName']}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        if (data['submittedFileUrl'] != null && data['submittedFileUrl'] != "") ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () {
                               // In a real app, you'd use url_launcher
                               // For now, we just show that it exists
                               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Opening file...")));
                            },
                            icon: const Icon(Icons.download, size: 16),
                            label: const Text("Download Submitted File", style: TextStyle(fontSize: 12)),
                          ),
                        ],
                        const Divider(),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 10,
                              backgroundImage: usersMap[data['submittedBy']]?['photoBase64'] != null && usersMap[data['submittedBy']]!['photoBase64'].isNotEmpty
                                ? MemoryImage(base64Decode(usersMap[data['submittedBy']]!['photoBase64'])) 
                                : null,
                              child: (usersMap[data['submittedBy']]?['photoBase64'] == null || usersMap[data['submittedBy']]!['photoBase64'].isEmpty)
                                ? const Icon(Icons.person, size: 10) 
                                : null,
                            ),
                            const SizedBox(width: 8),
                            Text("Submitted by: ${usersMap[data['submittedBy']]?['fullName'] ?? data['submittedBy']}",
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (canReview && !isAccepted) ...[
                    const Divider(height: 30),
                    const Text("ADMIN / CREATOR REVIEW", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF3F598F))),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          foregroundColor: Colors.green),
                      onPressed: () => _showReviewDialog(context, doc, data, true),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text("ACCEPT WORK", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          foregroundColor: Colors.orange.shade900),
                      onPressed: () => _showReviewDialog(context, doc, data, false),
                      icon: const Icon(Icons.history),
                      label: const Text("RETURN FOR CORRECTIONS", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
                if (canReview && !taskIsDone)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text("Pending submission...",
                              style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey)))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showReviewDialog(BuildContext context, DocumentSnapshot doc, Map<String, dynamic> data, bool isAccepting) {
    double selectedRating = isAccepting ? 5.0 : 3.0;
    final controller = TextEditingController();
    final taskId = doc.id;
    final taskTitle = data['title'];

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              return AlertDialog(
                  title: Text(isAccepting ? "Accept & Evaluate: $taskTitle" : "Remarks & Return: $taskTitle", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isAccepting) ...[
                          const Text("Give a rating for the work performance:"),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(5, (index) {
                              return IconButton(
                                icon: Icon(
                                  index < selectedRating ? Icons.star : Icons.star_border,
                                  color: Colors.amber,
                                  size: 32,
                                ),
                                onPressed: () {
                                  setDialogState(() {
                                    selectedRating = index + 1.0;
                                  });
                                },
                              );
                            }),
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            labelText: isAccepting ? "Final Remarks / Commendations" : "Reasons for Return / Remarks", 
                            border: const OutlineInputBorder()),
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                        )
                      ]),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: isAccepting ? Colors.green : Colors.orange.shade900),
                        onPressed: () async {
                          if (controller.text.trim().isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Please add remarks.")));
                            return;
                          }
                          
                          final batch = FirebaseFirestore.instance.batch();
                          final taskRef = FirebaseFirestore.instance.collection('tasks').doc(taskId);
                          final evalRef = FirebaseFirestore.instance.collection('evaluations').doc();

                          batch.set(evalRef, {
                            'taskId': taskId,
                            'rating': isAccepting ? selectedRating : 0,
                            'feedback': isAccepting ? "[ACCEPTED] ${controller.text.trim()}" : "[RETURNED] ${controller.text.trim()}",
                            'timestamp': FieldValue.serverTimestamp(),
                            'evaluatorEmail': FirebaseAuth.instance.currentUser?.email ?? "Unknown",
                          });

                          if (isAccepting) {
                            batch.update(taskRef, {
                              'isAccepted': true,
                              'acceptedAt': FieldValue.serverTimestamp(),
                              'status': 'Completed'
                            });
                          } else {
                            final updatedSubTasks = List<Map<String, dynamic>>.from(data['subTasks'] ?? []);
                            for (var i = 0; i < updatedSubTasks.length; i++) {
                              updatedSubTasks[i]['isDone'] = false;
                            }
                            batch.update(taskRef, {
                              'isDone': false,
                              'isAccepted': false,
                              'status': 'Returned',
                              'subTasks': updatedSubTasks,
                            });
                          }

                          await batch.commit();

                          // Notify assigned staff about the review (Accepted or Returned)
                          final List<String> assignedEmails = List<String>.from(data['assignedTo'] ?? []);
                          for (final email in assignedEmails) {
                            final title = isAccepting ? 'Work Accepted' : 'Work Returned';
                            final body = isAccepting 
                                ? 'Your submission for "$taskTitle" was accepted!'
                                : 'Your submission for "$taskTitle" was returned for corrections.';
                                
                            await FirebaseFirestore.instance.collection('notifications').add({
                              'to': email,
                              'title': title,
                              'taskName': taskTitle ?? '',
                              'eventTitle': taskTitle ?? '',
                              'isRead': false,
                              'createdAt': FieldValue.serverTimestamp(),
                              'body': body,
                            });
                            
                            // 🔥 Send real push notification via FCM
                            NotificationService.sendPushNotification(
                              toEmail: email,
                              title: title,
                              body: body,
                            );
                          }

                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            if (context.mounted) Navigator.pop(context); // Close sheet
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(isAccepting ? "Task Accepted!" : "Task Returned for Corrections"),
                              backgroundColor: isAccepting ? Colors.green : Colors.orange,
                            ));
                          }
                        },
                        child: Text(isAccepting ? "ACCEPT" : "RETURN", style: const TextStyle(color: Colors.white)))
                  ]);
            })
    );
  }

  // Deprecated _showRatingDialog removed for _showReviewDialog

  /// Writes a reminder notification to Firestore for each staff member assigned to [subTask].
  Future<void> _sendReminder(
    BuildContext context,
    Map<String, dynamic> subTask,
    String eventTitle,
    Map<String, dynamic> usersMap,
  ) async {
    final List<String> assignedEmails = List<String>.from(subTask['assignedTo'] ?? []);
    if (assignedEmails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No staff assigned to this task.')),
      );
      return;
    }

    final taskName = subTask['task'] ?? 'a task';
    final senderEmail = FirebaseAuth.instance.currentUser?.email ?? 'Admin';

    try {
      final Timestamp? deadlineTs = subTask['deadline'] as Timestamp?;
      String timeRemainingStr = "";
      if (deadlineTs != null) {
        final deadline = deadlineTs.toDate();
        final now = DateTime.now();
        final diff = deadline.difference(now);
        if (diff.isNegative) {
          timeRemainingStr = "\n\nTime Remaining: Overdue by ${diff.abs().inDays}d ${diff.abs().inHours % 24}h";
        } else {
          if (diff.inDays > 0) {
            timeRemainingStr = "\n\nTime Remaining: ${diff.inDays}d ${diff.inHours % 24}h";
          } else if (diff.inHours > 0) {
            timeRemainingStr = "\n\nTime Remaining: ${diff.inHours}h ${diff.inMinutes % 60}m";
          } else {
            timeRemainingStr = "\n\nTime Remaining: ${diff.inMinutes}m";
          }
        }
      }

      final batch = FirebaseFirestore.instance.batch();
      for (final email in assignedEmails) {
        final ref = FirebaseFirestore.instance.collection('notifications').doc();
        final bodyText = 'You have a pending task: "$taskName" under event "$eventTitle".$timeRemainingStr';
        
        batch.set(ref, {
          'to': email,
          'title': 'Task Reminder',
          'body': bodyText,
          'eventTitle': eventTitle,
          'taskName': taskName,
          'sentBy': senderEmail,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        // 🔥 Send real push notification via FCM
        NotificationService.sendPushNotification(
          toEmail: email,
          title: 'Task Reminder',
          body: bodyText,
        );
      }
      await batch.commit();

      if (context.mounted) {
        final names = assignedEmails
            .map((e) => usersMap[e]?['fullName'] ?? e)
            .join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reminder sent to: $names'),
            backgroundColor: const Color(0xFF3F598F),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send reminder: $e')),
        );
      }
    }
  }
}
