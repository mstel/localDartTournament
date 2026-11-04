import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'christmas_decorations.dart';
import 'theme_controller.dart';
import '../features/tournaments/data/tournament_storage.dart';
import '../features/tournaments/domain/tournament_models.dart';
import '../features/tournaments/presentation/widgets/run/tournament_second_screen_view.dart';
import '../shared/widgets/arrow_key_dropdown_navigation.dart';

CreatedTournament? resolveSecondScreenTournament(
  List<CreatedTournament> tournaments, {
  String? tournamentId,
}) {
  if (tournamentId != null && tournamentId.isNotEmpty) {
    for (final tournament in tournaments) {
      if (tournament.id == tournamentId) return tournament;
    }
    return null;
  }

  for (final tournament in tournaments.reversed) {
    if (tournament.finishedAt == null) return tournament;
  }
  return tournaments.isEmpty ? null : tournaments.last;
}

class SecondScreenStandaloneApp extends StatefulWidget {
  const SecondScreenStandaloneApp({super.key, this.tournamentId});

  final String? tournamentId;

  @override
  State<SecondScreenStandaloneApp> createState() =>
      _SecondScreenStandaloneAppState();
}

class _SecondScreenStandaloneAppState extends State<SecondScreenStandaloneApp> {
  @override
  void initState() {
    super.initState();
    AppThemeController.instance.load();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: AppThemeController.instance.themeModeNotifier,
    builder: (context, themeMode, _) => ValueListenableBuilder<AppThemeStyle>(
      valueListenable: AppThemeController.instance.themeStyleNotifier,
      builder: (context, style, _) {
        final christmas = style == AppThemeStyle.christmas;
        return MaterialApp(
          title: 'Dart Turnieranzeige (2. Bildschirm)',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: buildDartTournamentTheme(christmas: christmas),
          darkTheme: buildDartTournamentDarkTheme(christmas: christmas),
          builder: (context, child) {
            final app = ArrowKeyDropdownNavigation(
              child: child ?? const SizedBox.shrink(),
            );
            return christmas ? ChristmasDecorations(child: app) : app;
          },
          home: _SecondScreenStandalonePage(tournamentId: widget.tournamentId),
        );
      },
    ),
  );
}

class _SecondScreenStandalonePage extends StatefulWidget {
  const _SecondScreenStandalonePage({this.tournamentId});

  final String? tournamentId;

  @override
  State<_SecondScreenStandalonePage> createState() =>
      _SecondScreenStandalonePageState();
}

class _SecondScreenStandalonePageState
    extends State<_SecondScreenStandalonePage> {
  CreatedTournament? _tournament;
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadTournament();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadTournament(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTournament({bool silent = false}) async {
    try {
      final storage = TournamentStorage();
      final tournaments = await storage.loadTournaments();
      final matched = resolveSecondScreenTournament(
        tournaments,
        tournamentId: widget.tournamentId,
      );

      if (!mounted) return;
      setState(() {
        _tournament = matched;
        _loading = false;
      });
    } catch (_) {
      if (!silent && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _tournament == null) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: scheme.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: scheme.tertiary),
              SizedBox(height: 16),
              Text(
                'Lade 2. Bildschirmanzeige...',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (_tournament == null) {
      final requestedTournament =
          widget.tournamentId != null && widget.tournamentId!.isNotEmpty;
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: scheme.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tv_off, color: scheme.onSurfaceVariant, size: 48),
              const SizedBox(height: 16),
              Text(
                requestedTournament
                    ? 'Das angeforderte Turnier wurde nicht gefunden.'
                    : 'Kein aktives Turnier gefunden.',
                style: TextStyle(color: scheme.onSurface, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                requestedTournament
                    ? 'Bitte öffne die Anzeige erneut aus dem gewünschten Turnier.'
                    : 'Starte oder wähle ein Turnier am Hauptbildschirm.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => _loadTournament(),
                child: const Text('Erneut suchen'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: TournamentSecondScreenView(
          tournament: _tournament!,
          isStandaloneWindow: true,
          onClose: _closeStandaloneWindow,
        ),
      ),
    );
  }

  void _closeStandaloneWindow() {
    if (Platform.isAndroid || Platform.isIOS) {
      SystemNavigator.pop();
    } else {
      exit(0);
    }
  }
}
