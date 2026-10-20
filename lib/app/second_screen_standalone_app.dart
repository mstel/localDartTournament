import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import '../features/tournaments/data/tournament_storage.dart';
import '../features/tournaments/domain/tournament_models.dart';
import '../features/tournaments/presentation/widgets/run/tournament_second_screen_view.dart';

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

class SecondScreenStandaloneApp extends StatelessWidget {
  const SecondScreenStandaloneApp({super.key, this.tournamentId});

  final String? tournamentId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dart Turnieranzeige (2. Bildschirm)',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: buildDartTournamentTheme(),
      darkTheme: buildDartTournamentDarkTheme(),
      home: _SecondScreenStandalonePage(tournamentId: tournamentId),
    );
  }
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
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF70E0BA)),
              SizedBox(height: 16),
              Text(
                'Lade 2. Bildschirmanzeige...',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (_tournament == null) {
      final requestedTournament =
          widget.tournamentId != null && widget.tournamentId!.isNotEmpty;
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tv_off, color: Colors.white38, size: 48),
              const SizedBox(height: 16),
              Text(
                requestedTournament
                    ? 'Das angeforderte Turnier wurde nicht gefunden.'
                    : 'Kein aktives Turnier gefunden.',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                requestedTournament
                    ? 'Bitte öffne die Anzeige erneut aus dem gewünschten Turnier.'
                    : 'Starte oder wähle ein Turnier am Hauptbildschirm.',
                style: TextStyle(color: Colors.white54),
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
      backgroundColor: Colors.black,
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
