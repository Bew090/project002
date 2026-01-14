import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Import หน้าต่างๆ ของคุณ - แก้ path ให้ตรงกับโปรเจกต์
import 'pages/loginPage.dart';
import 'pages/main_navigation_page.dart';

// Import firebase_options.dart
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with options
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');
    
    // ตั้งค่า Persistence เป็น LOCAL สำหรับ Web (จำการล็อกอินแม้ปิด Browser)
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      print('Firebase Auth persistence set to LOCAL');
    }
  } catch (e) {
    print('Firebase initialization error: $e');
  }
  
  // Initialize locale
  await initializeDateFormatting('th_TH', null);
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Locker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Prompt', // ถ้าคุณใช้ฟอนต์ Prompt
      ),
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => const LoginPage(),
        // เพิ่ม routes อื่นๆ ถ้าต้องการ
      },
    );
  }
}

// Widget สำหรับตรวจสอบสถานะการล็อกอิน
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // แสดง Loading ขณะตรวจสอบสถานะ
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F7FA),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Color(0xFF667EEA),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'กำลังตรวจสอบสถานะ...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF667EEA),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // มี Error
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 80,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'เกิดข้อผิดพลาด',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${snapshot.error}',
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    child: const Text('กลับไปหน้า Login'),
                  ),
                ],
              ),
            ),
          );
        }

        // ตรวจสอบว่ามีผู้ใช้ล็อกอินอยู่หรือไม่
        final User? user = snapshot.data;

        if (user != null) {
          // ถ้ามีผู้ใช้ล็อกอินอยู่ -> ไปหน้าหลัก
          print('User logged in: ${user.uid}'); // Debug
          return MainNavigationPage(userId: user.uid);
        } else {
          // ถ้ายังไม่ได้ล็อกอิน -> ไปหน้า Login
          print('No user logged in'); // Debug
          return const LoginPage();
        }
      },
    );
  }
}