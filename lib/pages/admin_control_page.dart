// admin_control_page.dart
// หน้าควบคุมตู้ล็อกเกอร์สำหรับแอดมิน

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class AdminControlPage extends StatefulWidget {
  final String userId;
  
  const AdminControlPage({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<AdminControlPage> createState() => _AdminControlPageState();
}

class _AdminControlPageState extends State<AdminControlPage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final List<String> lockerCodes = ['A-001', 'A-002', 'A-003'];
  
  Map<String, Map<String, dynamic>> lockersData = {};
  Map<String, Map<String, dynamic>> usersData = {};
  bool isLoading = true;
  bool isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    try {
      // ตรวจสอบว่าเป็นแอดมินหรือไม่
      final userSnapshot = await _database.child('users/${widget.userId}').get();
      
      if (userSnapshot.exists) {
        final userData = userSnapshot.value as Map<dynamic, dynamic>;
        final email = userData['email'] as String?;
        
        // ตรวจสอบว่าเป็น admin email หรือไม่
        if (email == 'admin001@gmail.com') {
          setState(() {
            isAdmin = true;
          });
          // โหลดข้อมูลผู้ใช้ทั้งหมดก่อน
          await _preloadAllUsers();
          // แล้วค่อยโหลดข้อมูลตู้
          _loadAllData();
        } else {
          setState(() {
            isAdmin = false;
            isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking admin status: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _preloadAllUsers() async {
    try {
      final snapshot = await _database.child('users').get();
      if (!snapshot.exists) return;

      final usersMap = snapshot.value as Map<dynamic, dynamic>;
      
      usersMap.forEach((userId, userData) {
        if (userData is Map) {
          // ดึงข้อมูล name และ email ถ้าไม่มีให้ใช้ค่าเริ่มต้น
          String name = 'ไม่ระบุชื่อ';
          String email = 'ไม่ระบุอีเมล';
          
          // เช็คว่ามี name หรือไม่
          if (userData.containsKey('name') && userData['name'] != null) {
            name = userData['name'].toString();
          }
          
          // เช็คว่ามี email หรือไม่
          if (userData.containsKey('email') && userData['email'] != null) {
            email = userData['email'].toString();
          }
          
          setState(() {
            usersData[userId.toString()] = {
              'name': name,
              'email': email,
              'platform': userData['platform']?.toString() ?? 'web',
              'lastActive': userData['lastActive']?.toString(),
              'bookedAt': userData['bookedAt']?.toString(),
              'lockerCode': userData['lockerCode']?.toString(),
            };
          });
          
          debugPrint('Loaded user ${userId}: name=$name, email=$email');
        }
      });
      
      debugPrint('✅ Preloaded ${usersData.length} users');
    } catch (e) {
      debugPrint('❌ Error preloading users: $e');
    }
  }

  void _loadAllData() async {
    // โหลดข้อมูลตู้ทั้งหมด
    for (String lockerCode in lockerCodes) {
      _database.child('lockers/$lockerCode').onValue.listen((event) async {
        if (event.snapshot.exists && mounted) {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          
          setState(() {
            lockersData[lockerCode] = {
              'isLocked': data['isLocked'] ?? false,
              'currentUserId': data['currentUserId'],
              'bookingStartTime': data['bookingStartTime'],
              'bookingEndTime': data['bookingEndTime'],
              'bookingDuration': data['bookingDuration'],
            };
          });
          
          // ถ้าข้อมูลผู้ใช้ยังไม่มี ให้โหลดเพิ่ม
          final currentUserId = data['currentUserId'] as String?;
          if (currentUserId != null && !usersData.containsKey(currentUserId)) {
            await _loadUserData(currentUserId);
          }
        }
      });
    }
    
    // รอให้โหลดข้อมูลเสร็จ
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadUserData(String userId) async {
    try {
      final snapshot = await _database.child('users/$userId').get();
      if (snapshot.exists && mounted) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        
        // ดึงข้อมูล name และ email ถ้าไม่มีให้ใช้ค่าเริ่มต้น
        String userName = 'ไม่ระบุชื่อ';
        String userEmail = 'ไม่ระบุอีเมล';
        
        if (data.containsKey('name') && data['name'] != null) {
          userName = data['name'].toString();
        }
        
        if (data.containsKey('email') && data['email'] != null) {
          userEmail = data['email'].toString();
        }
        
        debugPrint('📝 Loaded user $userId: name=$userName, email=$userEmail');
        
        setState(() {
          usersData[userId] = {
            'name': userName,
            'email': userEmail,
            'platform': data['platform']?.toString() ?? 'web',
            'lastActive': data['lastActive']?.toString(),
            'bookedAt': data['bookedAt']?.toString(),
            'lockerCode': data['lockerCode']?.toString(),
          };
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading user $userId: $e');
      setState(() {
        usersData[userId] = {
          'name': 'Error: ${e.toString().substring(0, 20)}',
          'email': 'กรุณาตรวจสอบข้อมูล',
          'platform': 'unknown',
        };
      });
    }
  }

  Future<void> _adminToggleLock(String lockerCode) async {
    try {
      final currentLockState = lockersData[lockerCode]?['isLocked'] ?? false;
      final newLockState = !currentLockState;
      final now = DateTime.now().toUtc().add(const Duration(hours: 7));

      // แสดง Loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // อัพเดทสถานะล็อก
      await _database.child('lockers/$lockerCode/isLocked').set(newLockState);

      // สั่งรีเลย์
      await _database.child('lockers/$lockerCode/relay').update({
        'command': newLockState ? 'close' : 'open',
        'timestamp': now.toIso8601String(),
        'userId': 'admin_${widget.userId}',
        'status': 'pending',
      });

      // รอการตอบกลับจากรีเลย์
      bool relayExecuted = false;
      int waitTime = 0;
      
      while (!relayExecuted && waitTime < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        waitTime++;
        
        final relaySnapshot = await _database
            .child('lockers/$lockerCode/relay/status')
            .get();
            
        if (relaySnapshot.exists && relaySnapshot.value == 'completed') {
          relayExecuted = true;
        }
      }

      // บันทึกประวัติ
      final historyRef = _database.child('lockers/$lockerCode/history').push();
      await historyRef.set({
        'action': newLockState ? 'admin_lock' : 'admin_unlock',
        'timestamp': now.toIso8601String(),
        'userId': 'admin_${widget.userId}',
        'relayStatus': relayExecuted ? 'success' : 'timeout',
      });

      if (mounted) {
        Navigator.pop(context); // ปิด loading
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  newLockState 
                      ? 'ล็อกตู้ $lockerCode สำเร็จ' 
                      : 'ปลดล็อกตู้ $lockerCode สำเร็จ',
                ),
              ],
            ),
            backgroundColor: newLockState 
                ? const Color(0xFF48BB78) 
                : const Color(0xFFED8936),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // ปิด loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _adminForceReturn(String lockerCode) async {
    final currentUserId = lockersData[lockerCode]?['currentUserId'];
    
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ตู้นี้ไม่มีผู้ใช้งาน'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // ยืนยันการบังคับคืนตู้
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFED7D7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_rounded,
                color: Color(0xFFE53E3E),
              ),
            ),
            const SizedBox(width: 12),
            const Text('ยืนยันบังคับคืนตู้'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'คุณต้องการบังคับคืนตู้ $lockerCode ใช่หรือไม่?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFED7D7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.person, color: Color(0xFFE53E3E), size: 16),
                      SizedBox(width: 6),
                      Text(
                        'ผู้ใช้งานปัจจุบัน:',
                        style: TextStyle(
                          color: Color(0xFFE53E3E),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    usersData[currentUserId]?['name'] ?? 'ไม่ทราบชื่อ',
                    style: const TextStyle(
                      color: Color(0xFFE53E3E),
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    usersData[currentUserId]?['email'] ?? 'ไม่ทราบอีเมล',
                    style: const TextStyle(
                      color: Color(0xFFE53E3E),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53E3E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        final now = DateTime.now().toUtc().add(const Duration(hours: 7));
        final bookingStartTime = lockersData[lockerCode]?['bookingStartTime'];
        
        Duration? totalDuration;
        if (bookingStartTime != null) {
          try {
            final startTime = DateTime.parse(bookingStartTime);
            totalDuration = now.difference(startTime);
          } catch (e) {
            debugPrint('Error parsing start time: $e');
          }
        }

        // สั่งรีเลย์ปลดล็อกตู้
        await _database.child('lockers/$lockerCode/relay').update({
          'command': 'unlock_vacant',
          'timestamp': now.toIso8601String(),
          'userId': 'admin_force_return',
          'status': 'pending',
        });

        // รอการตอบกลับ
        bool relayExecuted = false;
        int waitTime = 0;
        
        while (!relayExecuted && waitTime < 10) {
          await Future.delayed(const Duration(milliseconds: 500));
          waitTime++;
          
          final relaySnapshot = await _database
              .child('lockers/$lockerCode/relay/status')
              .get();
              
          if (relaySnapshot.exists && relaySnapshot.value == 'completed') {
            relayExecuted = true;
          }
        }

        // บันทึกประวัติ
        final historyRef = _database.child('lockers/$lockerCode/history').push();
        await historyRef.set({
          'action': 'admin_force_returned',
          'timestamp': now.toIso8601String(),
          'duration': totalDuration?.inSeconds,
          'userId': currentUserId,
          'adminId': widget.userId,
          'relayStatus': relayExecuted ? 'success' : 'timeout',
        });

        // ลบข้อมูลผู้ใช้ออกจากตู้
        await _database.child('lockers/$lockerCode').update({
          'currentUserId': null,
          'isLocked': false,
          'bookingStartTime': null,
          'bookingEndTime': null,
          'bookingDuration': null,
        });

        // ลบรหัสตู้ออกจากผู้ใช้
        await _database.child('users/$currentUserId/lockerCode').remove();
        await _database.child('users/$currentUserId/bookedAt').remove();
        await _database.child('users/$currentUserId/bookingEndTime').remove();
        await _database.child('users/$currentUserId/bookingDuration').remove();

        if (mounted) {
          Navigator.pop(context); // ปิด loading
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Text('บังคับคืนตู้ $lockerCode สำเร็จ'),
                ],
              ),
              backgroundColor: const Color(0xFF48BB78),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('เกิดข้อผิดพลาด: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null) return '-';
    try {
      final dateTime = DateTime.parse(isoString);
      final formatter = DateFormat('dd/MM/yy HH:mm');
      return formatter.format(dateTime);
    } catch (e) {
      return '-';
    }
  }

  String _getRemainingTime(String? endTimeString) {
    if (endTimeString == null) return '-';
    try {
      final endTime = DateTime.parse(endTimeString);
      final remaining = endTime.difference(DateTime.now());
      
      if (remaining.isNegative) {
        return 'หมดเวลา';
      }
      
      final hours = remaining.inHours;
      final minutes = remaining.inMinutes.remainder(60);
      return '${hours}ชม ${minutes}นาที';
    } catch (e) {
      return '-';
    }
  }

  // Future<void> _showAllUsersDialog() async {
  //   showDialog(
  //     context: context,
  //     builder: (ctx) => Dialog(
  //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  //       child: Container(
  //         constraints: const BoxConstraints(maxHeight: 600),
  //         child: Column(
  //           mainAxisSize: MainAxisSize.min,
  //           children: [
  //             Container(
  //               padding: const EdgeInsets.all(20),
  //               decoration: const BoxDecoration(
  //                 gradient: LinearGradient(
  //                   colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
  //                   begin: Alignment.topLeft,
  //                   end: Alignment.bottomRight,
  //                 ),
  //                 borderRadius: BorderRadius.only(
  //                   topLeft: Radius.circular(20),
  //                   topRight: Radius.circular(20),
  //                 ),
  //               ),
  //               child: Row(
  //                 children: const [
  //                   Icon(Icons.people_rounded, color: Colors.white, size: 28),
  //                   SizedBox(width: 12),
  //                   Text(
  //                     'ผู้ใช้งานทั้งหมด',
  //                     style: TextStyle(
  //                       color: Colors.white,
  //                       fontSize: 20,
  //                       fontWeight: FontWeight.bold,
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //             Flexible(
  //               child: FutureBuilder<List<Map<String, dynamic>>>(
  //                 future: _loadAllUsers(),
  //                 builder: (context, snapshot) {
  //                   if (snapshot.connectionState == ConnectionState.waiting) {
  //                     return const Center(
  //                       child: Padding(
  //                         padding: EdgeInsets.all(40.0),
  //                         child: CircularProgressIndicator(),
  //                       ),
  //                     );
  //                   }

  //                   if (!snapshot.hasData || snapshot.data!.isEmpty) {
  //                     return const Center(
  //                       child: Padding(
  //                         padding: EdgeInsets.all(40.0),
  //                         child: Text('ไม่พบข้อมูลผู้ใช้'),
  //                       ),
  //                     );
  //                   }

  //                   final users = snapshot.data!;
  //                   return ListView.builder(
  //                     shrinkWrap: true,
  //                     padding: const EdgeInsets.all(16),
  //                     itemCount: users.length,
  //                     itemBuilder: (context, index) {
  //                       final user = users[index];
  //                       final hasLocker = user['lockerCode'] != null;
                        
  //                       return Container(
  //                         margin: const EdgeInsets.only(bottom: 12),
  //                         decoration: BoxDecoration(
  //                           color: const Color(0xFFF7FAFC),
  //                           borderRadius: BorderRadius.circular(12),
  //                           border: Border.all(
  //                             color: hasLocker 
  //                                 ? const Color(0xFF667EEA).withOpacity(0.3)
  //                                 : const Color(0xFFE2E8F0),
  //                           ),
  //                         ),
  //                         child: ListTile(
  //                           contentPadding: const EdgeInsets.all(12),
  //                           leading: Container(
  //                             padding: const EdgeInsets.all(10),
  //                             decoration: BoxDecoration(
  //                               color: hasLocker 
  //                                   ? const Color(0xFF667EEA).withOpacity(0.1)
  //                                   : const Color(0xFFEDF2F7),
  //                               borderRadius: BorderRadius.circular(10),
  //                             ),
  //                             child: Icon(
  //                               hasLocker 
  //                                   ? Icons.person_rounded 
  //                                   : Icons.person_outline_rounded,
  //                               color: hasLocker 
  //                                   ? const Color(0xFF667EEA)
  //                                   : const Color(0xFF718096),
  //                             ),
  //                           ),
  //                           title: Text(
  //                             user['name'] ?? 'ไม่ระบุชื่อ',
  //                             style: const TextStyle(
  //                               fontWeight: FontWeight.bold,
  //                               fontSize: 16,
  //                             ),
  //                           ),
  //                           subtitle: Column(
  //                             crossAxisAlignment: CrossAxisAlignment.start,
  //                             children: [
  //                               const SizedBox(height: 4),
  //                               Text(
  //                                 user['email'] ?? 'ไม่ระบุอีเมล',
  //                                 style: const TextStyle(
  //                                   fontSize: 13,
  //                                   color: Color(0xFF718096),
  //                                 ),
  //                               ),
  //                               if (hasLocker) ...[
  //                                 const SizedBox(height: 8),
  //                                 Container(
  //                                   padding: const EdgeInsets.symmetric(
  //                                     horizontal: 8,
  //                                     vertical: 4,
  //                                   ),
  //                                   decoration: BoxDecoration(
  //                                     color: const Color(0xFF667EEA),
  //                                     borderRadius: BorderRadius.circular(6),
  //                                   ),
  //                                   child: Row(
  //                                     mainAxisSize: MainAxisSize.min,
  //                                     children: [
  //                                       const Icon(
  //                                         Icons.inventory_2_rounded,
  //                                         color: Colors.white,
  //                                         size: 14,
  //                                       ),
  //                                       const SizedBox(width: 4),
  //                                       Text(
  //                                         'ตู้ ${user['lockerCode']}',
  //                                         style: const TextStyle(
  //                                           color: Colors.white,
  //                                           fontSize: 12,
  //                                           fontWeight: FontWeight.bold,
  //                                         ),
  //                                       ),
  //                                     ],
  //                                   ),
  //                                 ),
  //                               ],
  //                               if (user['lastActive'] != null) ...[
  //                                 const SizedBox(height: 4),
  //                                 Row(
  //                                   children: [
  //                                     const Icon(
  //                                       Icons.access_time_rounded,
  //                                       size: 12,
  //                                       color: Color(0xFF718096),
  //                                     ),
  //                                     const SizedBox(width: 4),
  //                                     Text(
  //                                       'ล่าสุด: ${_formatDateTime(user['lastActive'])}',
  //                                       style: const TextStyle(
  //                                         fontSize: 11,
  //                                         color: Color(0xFF718096),
  //                                       ),
  //                                     ),
  //                                   ],
  //                                 ),
  //                               ],
  //                             ],
  //                           ),
  //                           trailing: user['platform'] != null
  //                               ? Container(
  //                                   padding: const EdgeInsets.symmetric(
  //                                     horizontal: 8,
  //                                     vertical: 4,
  //                                   ),
  //                                   decoration: BoxDecoration(
  //                                     color: const Color(0xFFEDF2F7),
  //                                     borderRadius: BorderRadius.circular(6),
  //                                   ),
  //                                   child: Text(
  //                                     user['platform'] == 'web' ? 'Web' : 'Mobile',
  //                                     style: const TextStyle(
  //                                       fontSize: 11,
  //                                       color: Color(0xFF4A5568),
  //                                     ),
  //                                   ),
  //                                 )
  //                               : null,
  //                         ),
  //                       );
  //                     },
  //                   );
  //                 },
  //               ),
  //             ),
  //             Padding(
  //               padding: const EdgeInsets.all(16),
  //               child: SizedBox(
  //                 width: double.infinity,
  //                 child: ElevatedButton(
  //                   onPressed: () => Navigator.pop(ctx),
  //                   style: ElevatedButton.styleFrom(
  //                     backgroundColor: const Color(0xFF667EEA),
  //                     padding: const EdgeInsets.symmetric(vertical: 14),
  //                     shape: RoundedRectangleBorder(
  //                       borderRadius: BorderRadius.circular(12),
  //                     ),
  //                   ),
  //                   child: const Text(
  //                     'ปิด',
  //                     style: TextStyle(
  //                       fontSize: 16,
  //                       fontWeight: FontWeight.bold,
  //                     ),
  //                   ),
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }

  // Future<List<Map<String, dynamic>>> _loadAllUsers() async {
  //   try {
  //     final snapshot = await _database.child('users').get();
  //     if (!snapshot.exists) return [];

  //     final usersMap = snapshot.value as Map<dynamic, dynamic>;
  //     final usersList = <Map<String, dynamic>>[];

  //     usersMap.forEach((userId, userData) {
  //       if (userData is Map) {
  //         // ดึงข้อมูลแบบปลอดภัย
  //         String name = 'ไม่ระบุชื่อ';
  //         String email = 'ไม่ระบุอีเมล';
          
  //         if (userData.containsKey('name') && userData['name'] != null) {
  //           name = userData['name'].toString();
  //         }
          
  //         if (userData.containsKey('email') && userData['email'] != null) {
  //           email = userData['email'].toString();
  //         }
          
  //         usersList.add({
  //           'userId': userId.toString(),
  //           'name': name,
  //           'email': email,
  //           'lockerCode': userData['lockerCode']?.toString(),
  //           'platform': userData['platform']?.toString() ?? 'web',
  //           'lastActive': userData['lastActive']?.toString(),
  //           'bookedAt': userData['bookedAt']?.toString(),
  //         });
  //       }
  //     });

  //     // เรียงตามว่ามีตู้หรือไม่ แล้วตามชื่อ
  //     usersList.sort((a, b) {
  //       if (a['lockerCode'] != null && b['lockerCode'] == null) return -1;
  //       if (a['lockerCode'] == null && b['lockerCode'] != null) return 1;
  //       return (a['name'] ?? '').compareTo(b['name'] ?? '');
  //     });

  //     return usersList;
  //   } catch (e) {
  //     debugPrint('❌ Error loading all users: $e');
  //     return [];
  //   }
  // }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF718096),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'แอดมิน - ควบคุมตู้',
            style: TextStyle(
              color: Color(0xFF2D3748),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!isAdmin) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'แอดมิน - ควบคุมตู้',
            style: TextStyle(
              color: Color(0xFF2D3748),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                const Text(
                  'ไม่มีสิทธิ์เข้าถึง',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'คุณไม่มีสิทธิ์ใช้งานหน้านี้',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF718096),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'แอดมิน - ควบคุมตู้',
          style: TextStyle(
            color: Color(0xFF2D3748),
            fontWeight: FontWeight.bold,
          ),
        ),
        // actions: [
        //   IconButton(
        //     icon: const Icon(Icons.people_rounded, color: Color(0xFF667EEA)),
        //     tooltip: 'ดูผู้ใช้ทั้งหมด',
        //     onPressed: _showAllUsersDialog,
        //   ),
        //   IconButton(
        //     icon: const Icon(Icons.refresh, color: Color(0xFF2D3748)),
        //     onPressed: () async {
        //       setState(() {
        //         isLoading = true;
        //       });
        //       await _preloadAllUsers();
        //       _loadAllData();
        //     },
        //   ),
        // ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE53E3E), Color(0xFFFC8181)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE53E3E).withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.admin_panel_settings_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'ระบบควบคุมแอดมิน',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'จัดการตู้ทั้งหมด ${lockerCodes.length} ตู้',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // สถิติผู้ใช้งาน
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: const [
                      Icon(
                        Icons.analytics_rounded,
                        color: Color(0xFF667EEA),
                        size: 24,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'สถิติการใช้งาน',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3748),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'ตู้ทั้งหมด',
                          lockerCodes.length.toString(),
                          Icons.inventory_2_rounded,
                          const Color(0xFF667EEA),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'ตู้ว่าง',
                          lockersData.values.where((data) => data['currentUserId'] == null).length.toString(),
                          Icons.lock_open_rounded,
                          const Color(0xFF48BB78),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'กำลังใช้',
                          lockersData.values.where((data) => data['currentUserId'] != null).length.toString(),
                          Icons.lock_rounded,
                          const Color(0xFFE53E3E),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Lockers List
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: lockerCodes.length,
              itemBuilder: (context, index) {
                final lockerCode = lockerCodes[index];
                final lockerData = lockersData[lockerCode];
                final isLocked = lockerData?['isLocked'] ?? false;
                final currentUserId = lockerData?['currentUserId'];
                final isOccupied = currentUserId != null;
                final userData = currentUserId != null ? usersData[currentUserId] : null;
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isOccupied 
                          ? const Color(0xFFE53E3E).withOpacity(0.3)
                          : const Color(0xFF48BB78).withOpacity(0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isOccupied 
                              ? const Color(0xFFFED7D7)
                              : const Color(0xFFD4EDDA),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(18),
                            topRight: Radius.circular(18),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isOccupied 
                                    ? Icons.lock_rounded 
                                    : Icons.lock_open_rounded,
                                color: isOccupied 
                                    ? const Color(0xFFE53E3E)
                                    : const Color(0xFF48BB78),
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    lockerCode,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2D3748),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: isLocked
                                              ? const Color(0xFF48BB78)
                                              : const Color(0xFFED8936),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isLocked ? 'ล็อก' : 'ปลดล็อก',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isLocked
                                              ? const Color(0xFF48BB78)
                                              : const Color(0xFFED8936),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isOccupied
                                              ? const Color(0xFFE53E3E)
                                              : const Color(0xFF48BB78),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          isOccupied ? 'มีผู้ใช้' : 'ว่าง',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Content
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            if (isOccupied) ...[
                              // User Info
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF667EEA).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.person_rounded,
                                            color: Color(0xFF667EEA),
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'ผู้ใช้งาน',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF718096),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                userData?['name'] != null && userData!['name'] != 'ไม่ระบุชื่อ'
                                                    ? userData['name']
                                                    : currentUserId != null 
                                                        ? 'ผู้ใช้ ${currentUserId.substring(0, 8)}...'
                                                        : 'ไม่ทราบชื่อ',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF2D3748),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                userData?['email'] != null && userData!['email'] != 'ไม่ระบุอีเมล'
                                                    ? userData['email']
                                                    : 'ไม่มีข้อมูลอีเมล',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Color(0xFF718096),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (userData?['platform'] != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: const Color(0xFFE2E8F0),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  userData?['platform'] == 'web'
                                                      ? Icons.web_rounded
                                                      : Icons.phone_android_rounded,
                                                  size: 14,
                                                  color: const Color(0xFF718096),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  userData?['platform'] == 'web' ? 'Web' : 'App',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF718096),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    const Divider(),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: const [
                                                  Icon(
                                                    Icons.login_rounded,
                                                    size: 14,
                                                    color: Color(0xFF718096),
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'เริ่มจอง',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFF718096),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                lockerData?['bookingStartTime'] != null 
                                                    ? _formatDateTime(lockerData?['bookingStartTime'])
                                                    : userData?['bookedAt'] != null
                                                        ? _formatDateTime(userData?['bookedAt'])
                                                        : '-',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF2D3748),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: const [
                                                  Icon(
                                                    Icons.logout_rounded,
                                                    size: 14,
                                                    color: Color(0xFF718096),
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'สิ้นสุด',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFF718096),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                lockerData?['bookingEndTime'] != null
                                                    ? _formatDateTime(lockerData?['bookingEndTime'])
                                                    : userData?['bookingEndTime'] != null
                                                        ? _formatDateTime(userData?['bookingEndTime'])
                                                        : '-',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF2D3748),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFED7D7),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.timer_rounded,
                                            color: Color(0xFFE53E3E),
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            lockerData?['bookingEndTime'] != null
                                                ? 'เหลือเวลา: ${_getRemainingTime(lockerData?['bookingEndTime'])}'
                                                : userData?['bookingEndTime'] != null
                                                    ? 'เหลือเวลา: ${_getRemainingTime(userData?['bookingEndTime'])}'
                                                    : 'ไม่มีข้อมูลเวลาสิ้นสุด',
                                            style: const TextStyle(
                                              color: Color(0xFFE53E3E),
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            
                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _adminToggleLock(lockerCode),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isLocked
                                          ? const Color(0xFFED8936)
                                          : const Color(0xFF48BB78),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          isLocked 
                                              ? Icons.lock_open_rounded 
                                              : Icons.lock_rounded,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          isLocked ? 'ปลดล็อก' : 'ล็อก',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (isOccupied) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => _adminForceReturn(lockerCode),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFE53E3E),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: const [
                                          Icon(Icons.logout_rounded, size: 20),
                                          SizedBox(width: 8),
                                          Text(
                                            'บังคับคืน',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}