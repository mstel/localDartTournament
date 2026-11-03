import 'package:dart_tournament_manager/shared/widgets/arrow_key_dropdown_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('arrow keys cycle enabled dropdown values and wrap around', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    String selected = 'first';

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            ArrowKeyDropdownNavigation(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DropdownButton<String>(
              focusNode: focusNode,
              value: selected,
              items: const [
                DropdownMenuItem(value: 'first', child: Text('First')),
                DropdownMenuItem(
                  value: 'disabled',
                  enabled: false,
                  child: Text('Disabled'),
                ),
                DropdownMenuItem(value: 'last', child: Text('Last')),
              ],
              onChanged: (value) => setState(() => selected = value!),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(selected, 'last');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(selected, 'first');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(selected, 'last');
    expect(tester.takeException(), isNull);
  });

  testWidgets('form dropdown values can be changed with arrow keys', (
    tester,
  ) async {
    String? selected = 'first';

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            ArrowKeyDropdownNavigation(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DropdownButtonFormField<String>(
              initialValue: selected,
              items: const [
                DropdownMenuItem(value: 'first', child: Text('First')),
                DropdownMenuItem(value: 'second', child: Text('Second')),
              ],
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(selected, 'second');
    expect(tester.takeException(), isNull);
  });

  testWidgets('arrow keys still navigate an opened dropdown menu', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    String selected = 'first';

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            ArrowKeyDropdownNavigation(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DropdownButton<String>(
              focusNode: focusNode,
              value: selected,
              items: const [
                DropdownMenuItem(value: 'first', child: Text('First')),
                DropdownMenuItem(value: 'second', child: Text('Second')),
                DropdownMenuItem(value: 'third', child: Text('Third')),
              ],
              onChanged: (value) => setState(() => selected = value!),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, 'second');
    expect(tester.takeException(), isNull);
  });
}
