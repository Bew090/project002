// locker_control_page.dart
// ไฟล์นี้เป็นหน้าควบคุมตู้ล็อกเกอร์ที่เรียกใช้หลังจากล็อกอินแล้ว
// มีระบบนับเวลาถอยหลังและรีเลย์สำหรับล็อก/ปลดล็อกตู้

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'locker_selection_page.dart';

class LockerControlPage extends StatefulWidget {
  final String userId;
  final String lockerCode;
  
  const LockerControlPage({
    Key? key,
    required this.userId,
    required this.lockerCode,
  }) : super(key: key);

  @override
  State<LockerControlPage> createState() => _LockerControlPageState();
}

class _LockerControlPageState extends State<LockerControlPage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  bool isLocked = true;
  DateTime? bookingStartTime;
  DateTime? bookingEndTime; // เวลาที่สิ้นสุดการจอง
  Duration? remainingTime; // เวลาที่เหลือ
  int bookingDurationHours = 2; // ระยะเวลาการจองเริ่มต้น (2 ชั่วโมง)
  List<Map<String, dynamic>> bookingHistory = [];
  bool isLoading = true;
  String? errorMessage;
  bool isExpired = false; // เช็คว่าหมดเวลาหรือยัง
  
  @override
  void initState() {
    super.initState();
    if (widget.lockerCode.isEmpty) {
      setState(() {
        errorMessage = 'ไม่พบรหัสตู้ กรุณาเข้าสู่ระบบอีกครั้ง';
        isLoading = false;
      });
      return;
    }
    _initializeFirebase();
    _startTimeTracking();
  }

  void _initializeFirebase() async {
    try {
      final lockerSnapshot = await _database.child('lockers/${widget.lockerCode}').get();
      
      if (!lockerSnapshot.exists) {
        // สร้างข้อมูลเริ่มต้นพร้อมเวลาสิ้นสุด
        final now = DateTime.now().toUtc().add(const Duration(hours: 7));
        final endTime = now.add(Duration(hours: bookingDurationHours));
        
        await _database.child('lockers/${widget.lockerCode}').set({
          'isLocked': true,
          'bookingStartTime': now.toIso8601String(),
          'bookingEndTime': endTime.toIso8601String(),
          'bookingDurationHours': bookingDurationHours,
          'currentUserId': widget.userId,
          'relayPin': 'D1', // กำหนด pin ของรีเลย์ (ปรับตามฮาร์ดแวร์จริง)
        });
      } else {
        final data = lockerSnapshot.value as Map<dynamic, dynamic>;
        
        // ถ้าไม่มี bookingEndTime ให้สร้างใหม่
        if (data['bookingEndTime'] == null) {
          final now = DateTime.now().toUtc().add(const Duration(hours: 7));
          final startTime = data['bookingStartTime'] != null 
              ? DateTime.parse(data['bookingStartTime']) 
              : now;
          final duration = data['bookingDurationHours'] ?? bookingDurationHours;
          final endTime = startTime.add(Duration(hours: duration));
          
          await _database.child('lockers/${widget.lockerCode}/bookingEndTime').set(endTime.toIso8601String());
        }
      }

      // ฟังการเปลี่ยนแปลงสถานะล็อก
      _database.child('lockers/${widget.lockerCode}/isLocked').onValue.listen((event) {
        if (mounted) {
          setState(() {
            isLocked = event.snapshot.value as bool? ?? true;
            isLoading = false;
          });
        }
      });

      // ฟังเวลาเริ่มจอง
      _database.child('lockers/${widget.lockerCode}/bookingStartTime').onValue.listen((event) {
        if (mounted && event.snapshot.value != null) {
          setState(() {
            try {
              bookingStartTime = DateTime.parse(event.snapshot.value as String);
            } catch (e) {
              bookingStartTime = null;
            }
          });
        }
      });

      // ฟังเวลาสิ้นสุดการจอง
      _database.child('lockers/${widget.lockerCode}/bookingEndTime').onValue.listen((event) {
        if (mounted && event.snapshot.value != null) {
          setState(() {
            try {
              bookingEndTime = DateTime.parse(event.snapshot.value as String);
            } catch (e) {
              bookingEndTime = null;
            }
          });
        }
      });

      // โหลดระยะเวลาการจอง
      _database.child('lockers/${widget.lockerCode}/bookingDurationHours').onValue.listen((event) {
        if (mounted && event.snapshot.value != null) {
          setState(() {
            bookingDurationHours = event.snapshot.value as int;
          });
        }
      });

      await _loadBookingHistory();
      
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && isLoading) {
          setState(() {
            isLoading = false;
          });
        }
      });
      
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'ไม่สามารถเชื่อมต่อ Firebase: $e';
          isLoading = false;
        });
      }
    }
  }

  void _startTimeTracking() {
    // อัพเดทเวลาทุก 1 วินาที - นับถอยหลัง
    Stream.periodic(const Duration(seconds: 1)).listen((_) {
      if (mounted && bookingEndTime != null) {
        final now = DateTime.now();
        final remaining = bookingEndTime!.difference(now);
        
        setState(() {
          if (remaining.isNegative) {
            remainingTime = Duration.zero;
            isExpired = true;
            // ล็อกตู้อัตโนมัติเมื่อหมดเวลา
            if (!isLocked) {
              _autoLockLocker();
            }
          } else {
            remainingTime = remaining;
            isExpired = false;
          }
        });
      }
    });
  }

  Future<void> _autoLockLocker() async {
    try {
      final now = DateTime.now().toUtc().add(const Duration(hours: 7));
      
      // ส่งคำสั่งล็อกไปที่รีเลย์
      await _database.child('lockers/${widget.lockerCode}/relayCommand').set({
        'action': 'lock',
        'timestamp': now.toIso8601String(),
      });
      
      // อัพเดทสถานะล็อก
      await _database.child('lockers/${widget.lockerCode}/isLocked').set(true);
      
      // บันทึกประวัติ
      await _saveHistory('auto_lock', now, null);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('หมดเวลาการใช้งาน ตู้ถูกล็อกอัตโนมัติ'),
            backgroundColor: const Color(0xFFE53E3E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Auto lock error: $e');
    }
  }

  Future<void> _loadBookingHistory() async {
    try {
      final snapshot = await _database.child('lockers/${widget.lockerCode}/history').get();
      if (snapshot.exists && mounted) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          bookingHistory = data.entries.map((e) {
            final value = e.value as Map<dynamic, dynamic>;
            return {
              'action': value['action'],
              'timestamp': value['timestamp'],
              'duration': value['duration'],
              'userId': value['userId'] ?? '',
            };
          }).toList()
            ..sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
        });
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
    }
  }

  Future<void> _toggleLock() async {
    // ตรวจสอบว่าหมดเวลาหรือไม่
    if (isExpired) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('หมดเวลาการใช้งาน กรุณาคืนตู้'),
          backgroundColor: const Color(0xFFE53E3E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    try {
      final newLockState = !isLocked;
      final now = DateTime.now();
      final bangkokTime = now.toUtc().add(const Duration(hours: 7));

      // ส่งคำสั่งไปยังรีเลย์ผ่าน Firebase
      await _database.child('lockers/${widget.lockerCode}/relayCommand').set({
        'action': newLockState ? 'lock' : 'unlock',
        'timestamp': bangkokTime.toIso8601String(),
        'userId': widget.userId,
      });

      // อัพเดทสถานะล็อก
      await _database.child('lockers/${widget.lockerCode}/isLocked').set(newLockState);

      // บันทึกประวัติการล็อก/ปลดล็อก
      await _saveHistory(newLockState ? 'lock' : 'unlock', bangkokTime, null);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newLockState ? 'ส่งคำสั่งล็อกตู้สำเร็จ' : 'ส่งคำสั่งปลดล็อกตู้สำเร็จ'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: newLockState ? const Color(0xFF48BB78) : const Color(0xFFED8936),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }

      await _loadBookingHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _extendTime() async {
    // แสดง Dialog เพื่อเลือกเวลาที่ต้องการเพิ่ม
    final hours = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('เพิ่มเวลาการใช้งาน'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('+ 1 ชั่วโมง'),
              onTap: () => Navigator.pop(context, 1),
            ),
            ListTile(
              title: const Text('+ 2 ชั่วโมง'),
              onTap: () => Navigator.pop(context, 2),
            ),
            ListTile(
              title: const Text('+ 3 ชั่วโมง'),
              onTap: () => Navigator.pop(context, 3),
            ),
          ],
        ),
      ),
    );

    if (hours != null && bookingEndTime != null) {
      try {
        final newEndTime = bookingEndTime!.add(Duration(hours: hours));
        await _database.child('lockers/${widget.lockerCode}/bookingEndTime').set(newEndTime.toIso8601String());
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('เพิ่มเวลา $hours ชั่วโมงสำเร็จ'),
              backgroundColor: const Color(0xFF48BB78),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
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

  Future<void> _returnLocker() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFED7D7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFE53E3E),
              ),
            ),
            const SizedBox(width: 12),
            const Text('ยืนยันการคืนตู้'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'คุณต้องการคืนตู้ ${widget.lockerCode} ใช่หรือไม่?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFED7D7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.warning, color: Color(0xFFE53E3E), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'การคืนตู้จะลบข้อมูลและไม่สามารถกู้คืนได้',
                      style: TextStyle(
                        color: Color(0xFFE53E3E),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53E3E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('ยืนยันคืนตู้'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final now = DateTime.now().toUtc().add(const Duration(hours: 7));

        Duration? totalDuration;
        if (bookingStartTime != null) {
          totalDuration = now.difference(bookingStartTime!);
        }

        // ส่งคำสั่งล็อกตู้ก่อนคืน
        await _database.child('lockers/${widget.lockerCode}/relayCommand').set({
          'action': 'lock',
          'timestamp': now.toIso8601String(),
          'userId': widget.userId,
        });

        final historyRef = _database.child('lockers/${widget.lockerCode}/history').push();
        await historyRef.set({
          'action': 'returned',
          'timestamp': now.toIso8601String(),
          'duration': totalDuration?.inSeconds,
          'userId': widget.userId,
        });

        await _database.child('lockers/${widget.lockerCode}').update({
          'currentUserId': null,
          'isLocked': true,
          'bookingStartTime': null,
          'bookingEndTime': null,
          'relayCommand': null,
        });

        await _database.child('users/${widget.userId}/lockerCode').remove();

        if (mounted) {
          Navigator.pop(context);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('คืนตู้ ${widget.lockerCode} สำเร็จ'),
              backgroundColor: const Color(0xFF48BB78),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );

          await Future.delayed(const Duration(milliseconds: 500));
          
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => LockerSelectionPage(
                userId: widget.userId,
              ),
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

  void _backToSelection() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => LockerSelectionPage(
          userId: widget.userId,
        ),
      ),
    );
  }

  Future<void> _saveHistory(String action, DateTime timestamp, Duration? duration) async {
    final historyRef = _database.child('lockers/${widget.lockerCode}/history').push();
    await historyRef.set({
      'action': action,
      'timestamp': timestamp.toIso8601String(),
      'duration': duration?.inSeconds,
      'userId': widget.userId,
    });
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      final formatter = DateFormat('dd/MM/yyyy HH:mm:ss');
      return formatter.format(dateTime);
    } catch (e) {
      return isoString;
    }
  }

  String _getActionText(String action) {
    switch (action) {
      case 'unlock':
        return 'ปลดล็อก';
      case 'lock':
        return 'ล็อก';
      case 'booked':
        return 'จองตู้';
      case 'returned':
        return 'คืนตู้';
      case 'auto_lock':
        return 'ล็อกอัตโนมัติ (หมดเวลา)';
      default:
        return action;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      errorMessage = null;
                      isLoading = true;
                    });
                    _initializeFirebase();
                  },
                  child: const Text('ลองอีกครั้ง'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _backToSelection,
                  child: const Text('กลับ'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'กำลังโหลดข้อมูล...',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF718096),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2D3748)),
          onPressed: _backToSelection,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF2D3748)),
            onPressed: _loadBookingHistory,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ตู้ล็อกเกอร์ของฉัน',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'จัดการและควบคุมตู้ของคุณ',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF718096),
                  ),
                ),
                const SizedBox(height: 40),
                
                // Locker Info Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667EEA).withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'รหัสตู้',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.lockerCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Countdown Timer Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isExpired 
                          ? [const Color(0xFFE53E3E), const Color(0xFFC53030)]
                          : [const Color(0xFF48BB78), const Color(0xFF38A169)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (isExpired 
                            ? const Color(0xFFE53E3E) 
                            : const Color(0xFF48BB78)).withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isExpired ? Icons.alarm_off : Icons.alarm,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isExpired ? 'หมดเวลาการใช้งาน' : 'เวลาที่เหลือ',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (remainingTime != null)
                        Text(
                          _formatDuration(remainingTime!),
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                      if (isExpired) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'กรุณาคืนตู้',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _extendTime,
                          icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                          label: const Text(
                            'เพิ่มเวลา',
                            style: TextStyle(color: Colors.white),
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.2),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Status Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isLocked
                              ? const Color(0xFFEDF2F7)
                              : const Color(0xFFFED7D7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                          color: isLocked
                              ? const Color(0xFF4A5568)
                              : const Color(0xFFE53E3E),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'สถานะตู้',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF718096),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isLocked ? 'ล็อก' : 'ปลดล็อก',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: isLocked
                                    ? const Color(0xFF2D3748)
                                    : const Color(0xFFE53E3E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isLocked
                              ? const Color(0xFF48BB78)
                              : const Color(0xFFED8936),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (isLocked
                                      ? const Color(0xFF48BB78)
                                      : const Color(0xFFED8936))
                                  .withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Control Button
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: isExpired ? null : _toggleLock,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLocked
                          ? const Color(0xFFED8936)
                          : const Color(0xFF48BB78),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      disabledBackgroundColor: const Color(0xFFCBD5E0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isExpired 
                              ? 'หมดเวลาการใช้งาน'
                              : (isLocked ? 'ปลดล็อกตู้' : 'ล็อกตู้'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Return Locker Button
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: OutlinedButton(
                    onPressed: _returnLocker,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE53E3E),
                      side: const BorderSide(color: Color(0xFFE53E3E), width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.logout_rounded, size: 24),
                        SizedBox(width: 12),
                        Text(
                          'คืนตู้ล็อกเกอร์',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Booking History
                const Text(
                  'ประวัติการใช้งาน',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 20),
                
                if (bookingHistory.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        'ยังไม่มีประวัติการใช้งาน',
                        style: TextStyle(
                          color: Color(0xFF718096),
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: bookingHistory.length,
                    itemBuilder: (context, index) {
                      final history = bookingHistory[index];
                      final action = history['action'] as String;
                      
                      IconData icon;
                      Color iconColor;
                      Color bgColor;
                      
                      switch (action) {
                        case 'unlock':
                          icon = Icons.lock_open_rounded;
                          iconColor = const Color(0xFFE53E3E);
                          bgColor = const Color(0xFFFED7D7);
                          break;
                        case 'lock':
                          icon = Icons.lock_rounded;
                          iconColor = const Color(0xFF4A5568);
                          bgColor = const Color(0xFFEDF2F7);
                          break;
                        case 'auto_lock':
                          icon = Icons.lock_clock;
                          iconColor = const Color(0xFFED8936);
                          bgColor = const Color(0xFFFFE5D0);
                          break;
                        case 'booked':
                          icon = Icons.check_circle;
                          iconColor = const Color(0xFF48BB78);
                          bgColor = const Color(0xFFD4EDDA);
                          break;
                        case 'returned':
                          icon = Icons.logout_rounded;
                          iconColor = const Color(0xFFED8936);
                          bgColor = const Color(0xFFFFE5D0);
                          break;
                        default:
                          icon = Icons.info;
                          iconColor = const Color(0xFF4A5568);
                          bgColor = const Color(0xFFEDF2F7);
                      }
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(icon, color: iconColor, size: 24),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getActionText(action),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2D3748),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDateTime(history['timestamp']),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF718096),
                                    ),
                                  ),
                                  if (action == 'returned' && history['duration'] != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'ระยะเวลาที่ใช้: ${_formatDuration(Duration(seconds: history['duration']))}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF4A5568),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
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
        ),
      ),
    );
  }
}