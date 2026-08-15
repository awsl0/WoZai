import 'package:flutter/material.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'state/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Session.instance.init();
  runApp(const WozaiApp());
}

class WozaiApp extends StatelessWidget {
  const WozaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WoZai',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF6B81)),
        useMaterial3: true,
      ),
      initialRoute: Session.instance.isLoggedIn ? '/home' : '/login',
      routes: {
        '/login': (_) => const LoginPage(),
        '/home': (_) => const HomePage(),
      },
    );
  }
}
