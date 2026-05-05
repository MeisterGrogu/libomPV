import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'providers/dashboard_provider.dart';
import 'screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE', null);

  runApp(
    const SchulCockpitApp(),
  );
}

class SchulCockpitApp extends StatelessWidget {
  const SchulCockpitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SchulCockpit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const _InitializerWidget(),
    );
  }
}

class _InitializerWidget extends StatefulWidget {
  const _InitializerWidget();

  @override
  State<_InitializerWidget> createState() => _InitializerWidgetState();
}

class _InitializerWidgetState extends State<_InitializerWidget> {
  late Future<DashboardProvider> _providerFuture;

  @override
  void initState() {
    super.initState();
    _providerFuture = _initializeProvider();
  }

  Future<DashboardProvider> _initializeProvider() async {
    final provider = DashboardProvider();
    await provider.initialize();
    await provider.refreshData();
    return provider;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardProvider>(
      future: _providerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Fehler: ${snapshot.error}')),
          );
        }
        return ChangeNotifierProvider<DashboardProvider>.value(
          value: snapshot.data!,
          child: const MainScreen(),
        );
      },
    );
  }
}