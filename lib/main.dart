import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'services/remote_config_service.dart';
import 'core/routes/app_router.dart';
import 'providers/auth_provider.dart';
import 'providers/bulletin_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase init
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Remote Config init (API keys için)
  final remoteConfig = RemoteConfigService();
  await remoteConfig.initialize();
  
  // Debug: Config değerlerini göster (production'da kaldır)
  if (const bool.fromEnvironment('dart.vm.product') == false) {
    remoteConfig.printAllConfigs();
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => BulletinProvider()),
      ],
      child: MaterialApp.router(
        title: 'AI Spor Pro',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
        ),
        routerConfig: router,
      ),
    );
  }
}