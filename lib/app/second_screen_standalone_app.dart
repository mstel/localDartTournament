import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import '../features/tournaments/data/tournament_storage.dart';
import '../features/tournaments/domain/tournament_models.dart';
import '../features/tournaments/presentation/widgets/run/tournament_second_screen_view.dart';

class SecondScreenStandaloneApp extends StatelessWidget {
  const SecondScreenStandaloneApp({super.key, this.tournamentId});

  final String? tournamentId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DartTournamentPro · Zweitbildschirm',
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
      CreatedTournament? matched;

      if (widget.tournamentId != null && widget.tournamentId!.isNotEmpty) {
        matched = tournaments
            .where((t) => t.id == widget.tournamentId)
            .firstOrNull;
      }

      matched ??=
          tournaments.where((t) => t.finishedAt == null).lastOrNull ??
          tournaments.lastOrNull;

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
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tv_off, color: Colors.white38, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Kein aktives Turnier gefunden.',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text(
                'Starte oder wähle ein Turnier am Hauptbildschirm.',
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
          onClose: SystemNavigator.pop,
        ),
      ),
    );
  }
}
