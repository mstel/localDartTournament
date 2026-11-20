import 'package:flutter/material.dart';

import '../../../../../shared/widgets/adaptive_content.dart';
import '../../../domain/second_screen_dialog_requests.dart';

/// Hinweisdialog nach „Neu einteilen“ auf dem Zweitmonitor.
///
/// „Übernehmen“ schließt nur den Dialog. Die Anzeige selbst wird vom Monitor
/// als erledigt markiert, damit ein erneutes Öffnen denselben Request nicht
/// wiederholt anzeigt. Eine inhaltliche Bestätigung wird nicht gespeichert.
class SecondScreenGroupAssignmentDialog extends StatelessWidget {
  const SecondScreenGroupAssignmentDialog({super.key, required this.request});

  final SecondScreenGroupAssignmentRequest request;

  static Future<bool?> show({
    required BuildContext context,
    required SecondScreenGroupAssignmentRequest request,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SecondScreenGroupAssignmentDialog(request: request),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title =
        'Gruppenzuweisung beendet: ausgewählter modus - ${request.modeLabel}';
    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.groups_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      key: const ValueKey('group-assignment-dialog-title'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: AdaptiveContentList(
                maxWidth: 980,
                padding: const EdgeInsets.all(16),
                children: [
                  for (final group in request.groups)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              group.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final member in group.members)
                                  Chip(label: Text(member)),
                              ],
                            ),
                            if (group.members.isEmpty)
                              Text(
                                'Keine Teilnehmer zugeordnet',
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (request.groups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('Keine Gruppen vorhanden.')),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                key: const ValueKey('group-assignment-dialog-confirm'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Übernehmen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
