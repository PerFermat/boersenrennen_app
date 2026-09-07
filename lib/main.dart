import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/bestenliste.dart';
import 'data/kursdaten_repository.dart';
import 'screens/start_screen.dart';
import 'theme/arcade_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');
  final prefs = await SharedPreferences.getInstance();

  runApp(BoersenrennenApp(prefs: prefs));
}

class BoersenrennenApp extends StatelessWidget {
  final SharedPreferences prefs;

  const BoersenrennenApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => KursdatenRepository()),
        ChangeNotifierProvider(create: (_) => BestenlisteRepository(prefs)),
      ],
      child: MaterialApp(
        title: 'Börsenrennen',
        debugShowCheckedModeBanner: false,
        theme: arcadeTheme(),
        locale: const Locale('de', 'DE'),
        supportedLocales: const [Locale('de', 'DE')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const StartScreen(),
      ),
    );
  }
}
