import 'package:flutter/material.dart';

import '../../../domain/tournament_models.dart';

class DirectorBoardSettingsEditor extends StatefulWidget {
  const DirectorBoardSettingsEditor({
    super.key,
    required this.tournament,
    required this.onSave,
  });

  final CreatedTournament tournament;
  final Future<void> Function(int board, String name, String liveUrl) onSave;

  @override
  State<DirectorBoardSettingsEditor> createState() =>
      _DirectorBoardSettingsEditorState();
}

class _DirectorBoardSettingsEditorState
    extends State<DirectorBoardSettingsEditor> {
  final Map<int, TextEditingController> _nameControllers = {};
  final Map<int, TextEditingController> _urlControllers = {};
  final Set<int> _savingBoards = {};

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant DirectorBoardSettingsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  void _syncControllers() {
    for (var board = 1; board <= widget.tournament.boardCount; board++) {
      _nameControllers.putIfAbsent(
        board,
        () => TextEditingController(
          text: widget.tournament.directorBoardNames[board] ?? '',
        ),
      );
      _urlControllers.putIfAbsent(
        board,
        () => TextEditingController(
          text: widget.tournament.directorBoardLiveUrls[board] ?? '',
        ),
      );
    }
    final removed = _nameControllers.keys
        .where((board) => board > widget.tournament.boardCount)
        .toList();
    for (final board in removed) {
      _nameControllers.remove(board)?.dispose();
      _urlControllers.remove(board)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    for (final controller in _urlControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save(int board) async {
    final rawUrl = _urlControllers[board]!.text.trim();
    if (rawUrl.isNotEmpty) {
      final uri = Uri.tryParse(rawUrl);
      if (uri == null ||
          !uri.hasAuthority ||
          !['http', 'https'].contains(uri.scheme.toLowerCase())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bitte eine gültige HTTP- oder HTTPS-URL eingeben.'),
          ),
        );
        return;
      }
    }
    setState(() => _savingBoards.add(board));
    try {
      await widget.onSave(
        board,
        _nameControllers[board]!.text.trim(),
        _urlControllers[board]!.text.trim(),
      );
    } finally {
      if (mounted) setState(() => _savingBoards.remove(board));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var board = 1; board <= widget.tournament.boardCount; board++)
        Card(
          key: ValueKey('director-board-settings-$board'),
          margin: const EdgeInsets.only(top: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.tournament.boardDisplayName(board),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fields = <Widget>[
                      TextField(
                        controller: _nameControllers[board],
                        decoration: const InputDecoration(
                          labelText: 'Board-Name',
                          hintText: 'z. B. Board 1',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        controller: _urlControllers[board],
                        decoration: InputDecoration(
                          labelText: 'Live Board URL',
                          hintText: 'https://…',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: 'Live Board URL leeren',
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            onPressed: () {
                              _urlControllers[board]!.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear),
                          ),
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(board),
                      ),
                    ];
                    if (constraints.maxWidth >= 740) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: fields[0]),
                          const SizedBox(width: 12),
                          Expanded(child: fields[1]),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        fields[0],
                        const SizedBox(height: 8),
                        fields[1],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _savingBoards.contains(board)
                        ? null
                        : () => _save(board),
                    icon: _savingBoards.contains(board)
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Board-Einstellungen speichern'),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
