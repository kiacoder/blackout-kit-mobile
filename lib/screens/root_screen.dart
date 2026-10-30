/// Root navigation screen - handles tab switching between main screens

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/intent_service.dart';
import 'config_import_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({Key? key}) : super(key: key);

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late PageController _pageController;

  static const List<Widget> _screens = [
    HomeScreen(),
    LibraryScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);
    // Cold start via "Open with"/share: the payload was queued natively
    // before the engine existed. Warm starts re-check on every resume
    // (onNewIntent fires while we're in the background).
    _checkIncomingIntent();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkIncomingIntent();
    }
  }

  Future<void> _checkIncomingIntent() async {
    final payload = await IntentService.consumePending();
    if (payload == null || !mounted) return;
    ConfigImportScreen.pendingPayload = payload;
    if (!mounted) return;
    await Get.to(() => const ConfigImportScreen());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.power),
            label: 'connect'.tr,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.library_books),
            label: 'library'.tr,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings),
            label: 'settings'.tr,
          ),
        ],
      ),
    );
  }
}
