import 'package:flutter/material.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'state/session.dart';
import 'theme/app_themes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Session.instance.init();
  runApp(const WozaiApp());
}

class WozaiApp extends StatelessWidget {
  const WozaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Session.themeNotifier,
      builder: (context, index, _) {
        final spec = appThemes[index.clamp(0, appThemes.length - 1)];
        return MaterialApp(
          title: 'WoZai',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(spec),
          initialRoute: Session.instance.isLoggedIn ? '/home' : '/login',
          routes: {
            '/login': (_) => const LoginPage(),
            '/home': (_) => const HomePage(),
          },
        );
      },
    );
  }
}
