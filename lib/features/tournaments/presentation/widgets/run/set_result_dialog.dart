import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../domain/tournament_models.dart';
import '../../../domain/set_result_validation.dart';
import '../../models/match_result.dart';
import 'best_performance_editor.dart';
import '../../../../statistics/domain/best_performance.dart';

class SetResultDialog extends StatefulWidget {
  const SetResultDialog({
    super.key,
    required this.match,
    required this.format,
    this.allowAdministration = true,
  });
  final bool allowAdministration;
  final GroupMatch match;
  final TournamentGameFormat format;
  @override
  State<SetResultDialog> createState() => _SetResultDialogState();
}

class _SetResultDialogState extends State<SetResultDialog> {
  late final List<TextEditingController> fields;
  late final List<FocusNode> focusNodes;
  String? error;
  bool recordBestPerformances = false;
  List<BestPerformance> bestPerformances = [];
  @override
  void initState() {
    super.initState();
    bestPerformances = [...widget.match.bestPerformances];
    recordBestPerformances = bestPerformances.isNotEmpty;
    fields = [
      for (final value in [
        widget.match.homeSets,
        widget.match.awaySets,
        widget.match.homeLegs,
        widget.match.awayLegs,
      ])
        TextEditingController(text: value?.toString() ?? '0'),
    ];
    focusNodes = List.generate(4, (index) {
      final fn = FocusNode();
      fn.addListener(() {
        if (fn.hasFocus) {
          _selectDefaultZero(index);
        }
      });
      return fn;
    });
  }

  @override
  void dispose() {
    for (final fn in focusNodes) {
      fn.dispose();
    }
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  Widget _stepperSuffix(TextEditingController controller, int Function() max) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          canRequestFocus: false,
          onTap: () {
            final current = int.tryParse(controller.text) ?? 0;
            if (current < max()) {
              controller.text = '${current + 1}';
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
            }
          },
          child: const Icon(Icons.arrow_drop_up, size: 22),
        ),
        InkWell(
          canRequestFocus: false,
          onTap: () {
            final current = int.tryParse(controller.text) ?? 0;
            if (current > 0) {
              controller.text = '${current - 1}';
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
            }
          },
          child: const Icon(Icons.arrow_drop_down, size: 22),
        ),
      ],
    );
  }

  void save() {
    final values = fields.map((f) => int.tryParse(f.text)).toList();
    if (values.any((v) => v == null) ||
        !isValidSetResult(
          widget.format,
          homeSets: values[0]!,
          awaySets: values[1]!,
          homeLegs: values[2]!,
          awayLegs: values[3]!,
        )) {
      setState(
        () => error =
            'Bitte ein vollständiges Set-Ergebnis mit dazu passenden Leg-Summen eingeben.',
      );
      return;
    }
    Navigator.of(context).pop(
      MatchResult(
        homeSets: values[0],
        awaySets: values[1],
        homeLegs: values[2],
        awayLegs: values[3],
        bestPerformances: recordBestPerformances ? bestPerformances : const [],
      ),
    );
  }

  Widget scoreRow(String label, int start) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 8),
      Row(
        children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: Builder(
                builder: (context) {
                  final index = start + i;
                  return TextField(
                    key: ValueKey('set-result-$index'),
                    controller: fields[index],
                    focusNode: focusNodes[index],
                    autofocus: index == 0,
                    keyboardType: TextInputType.number,
                    textInputAction: index < 3
                        ? TextInputAction.next
                        : TextInputAction.done,
                    inputFormatters: [
                      _ScoreLimitInputFormatter(() => _maximumFor(index)),
                    ],
                    onTap: () => _selectDefaultZero(index),
                    onSubmitted: (_) {
                      if (index < 3) {
                        focusNodes[index + 1].requestFocus();
                        _selectDefaultZero(index + 1);
                      } else {
                        save();
                      }
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: i == 0
                          ? widget.match.homePlayer?.name
                          : widget.match.awayPlayer?.name,
                      suffixIcon: _stepperSuffix(
                        fields[index],
                        () => _maximumFor(index),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    ],
  );

  void _selectDefaultZero(int index) {
    final controller = fields[index];
    if (controller.text == '0') {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    }
  }

  int _maximumFor(int index) {
    final setsToWin = widget.format.bestOfSets ~/ 2 + 1;
    final legsToWin = widget.format.bestOfLegs ~/ 2 + 1;
    if (index < 2) return setsToWin;
    final wonSets = int.tryParse(fields[index - 2].text) ?? 0;
    final lostSets = int.tryParse(fields[index == 2 ? 1 : 0].text) ?? 0;
    return wonSets * legsToWin + lostSets * (legsToWin - 1);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set-Ergebnis eingeben'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.format.label),
            const SizedBox(height: 16),
            scoreRow('Gewonnene Sets', 0),
            const SizedBox(height: 16),
            scoreRow('Gewonnene Legs insgesamt (für die Tabelle)', 2),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: recordBestPerformances,
              title: const Text('Bestleistung erfassen'),
              onChanged: (value) => setState(() {
                recordBestPerformances = value ?? false;
                if (!recordBestPerformances) bestPerformances = [];
              }),
            ),
            if (recordBestPerformances)
              BestPerformanceEditor(
                match: widget.match,
                initial: bestPerformances,
                onChanged: (items) => bestPerformances = items,
              ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      if (widget.allowAdministration &&
          (widget.match.hasScore || widget.match.isAnnulled))
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const MatchResult.cleared()),
          child: const Text('Ergebnis entfernen'),
        ),
      if (widget.allowAdministration)
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const MatchResult.annulled()),
          child: const Text('Spiel annullieren'),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Abbrechen'),
      ),
      FilledButton(onPressed: save, child: const Text('Speichern')),
    ],
  );
}

class _ScoreLimitInputFormatter extends TextInputFormatter {
  const _ScoreLimitInputFormatter(this.maximum);

  final int Function() maximum;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final value = int.tryParse(newValue.text);
    return value != null && value <= maximum() ? newValue : oldValue;
  }
}
