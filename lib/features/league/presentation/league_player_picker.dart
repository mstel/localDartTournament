import 'package:flutter/material.dart';

import '../../tournaments/data/app_database.dart';
import '../../tournaments/domain/tournament_models.dart';

class LeaguePlayerChoice {
  const LeaguePlayerChoice(this.player);
  final TournamentPlayer player;
}

class LeaguePlayerPicker extends StatefulWidget {
  const LeaguePlayerPicker({super.key, this.database});
  final LocalAppDatabase? database;

  @override
  State<LeaguePlayerPicker> createState() => _LeaguePlayerPickerState();
}

class _LeaguePlayerPickerState extends State<LeaguePlayerPicker> {
  late final _database = widget.database ?? LocalAppDatabase();
  final _search = TextEditingController();
  Future<List<PlayerProfile>>? _profiles;

  @override
  void initState() {
    super.initState();
    _profiles = _database.loadPlayerProfiles();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Spieler auswählen'),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'Spieler suchen',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: FutureBuilder<List<PlayerProfile>>(
              future: _profiles,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final query = _search.text.trim().toLowerCase();
                final profiles = (snapshot.data ?? const <PlayerProfile>[])
                    .where(
                      (profile) =>
                          profile.isActive &&
                          (query.isEmpty ||
                              profile.displayName.toLowerCase().contains(
                                query,
                              )),
                    )
                    .toList();
                if (profiles.isEmpty) {
                  return const Center(child: Text('Keine Spieler gefunden.'));
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    return ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(profile.displayName),
                      onTap: () => Navigator.pop(
                        context,
                        LeaguePlayerChoice(
                          TournamentPlayer(
                            name: profile.displayName,
                            profileId: profile.id,
                            isGenerated: false,
                            compactName: profile.compactDisplayName,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
    ],
  );
}
