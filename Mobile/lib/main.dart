import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/device_storage.dart';
import 'data/repositories/device_repository.dart';
import 'presentation/screens/onboarding/onboarding_screen.dart';
import 'presentation/screens/my_devices/my_devices_screen.dart';
import 'presentation/screens/connection_mode/connection_mode_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const PixelTreeApp());
}

class PixelTreeApp extends StatelessWidget {
  const PixelTreeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) =>
          AppLocalizations.of(context)?.appName ?? 'PixelTree',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supportedLocales) {
        // If Polish, use Polish. Otherwise, use English.
        if (locale?.languageCode == 'pl') {
          return const Locale('pl');
        }
        return const Locale('en');
      },
      home: const SplashScreen(),
    );
  }
}

// Splash screen with auto-navigation
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSavedDevices();
  }

  Future<void> _checkSavedDevices() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // Check for saved devices
    try {
      final prefs = await SharedPreferences.getInstance();
      final storage = DeviceStorage(prefs);
      final repository = DeviceRepository(storage);

      final hasDevices = await repository.hasDevices();

      if (!mounted) return;

      if (hasDevices) {
        // Navigate to My Devices
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MyDevicesScreen()),
        );
      } else {
        // Check if user opted to skip onboarding
        final skipOnboarding = prefs.getBool('skip_onboarding') ?? false;

        if (skipOnboarding) {
          // Skip onboarding - go directly to add device
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ConnectionModeScreen()),
          );
        } else {
          // Navigate to Onboarding
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
          );
        }
      }
    } catch (e) {
      // Error loading - go to onboarding
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.park, size: 100, color: Colors.white),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context)?.appName ?? 'PixelTree',
                style: Theme.of(
                  context,
                ).textTheme.displayLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)?.appTagline ?? '',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 48),
              const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
