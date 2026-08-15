import 'package:flutter/material.dart';
import 'home_tab_page.dart';
import 'timeline_page.dart';
import 'places_page.dart';
import 'settings_page.dart';
import 'record_page.dart';

/// 主外壳：4 个 tab（主页 / 时间线 / 地点线 / 设置）
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final showFab = _tab == 0 || _tab == 1;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeTabPage(onViewAll: () => setState(() => _tab = 1)),
          const TimelinePage(),
          const PlacesPage(),
          const SettingsPage(),
        ],
      ),
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecordPage()));
              },
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('记录此刻'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '主页'),
          NavigationDestination(icon: Icon(Icons.timeline), label: '时间线'),
          NavigationDestination(icon: Icon(Icons.place_outlined), selectedIcon: Icon(Icons.place), label: '地点线'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
