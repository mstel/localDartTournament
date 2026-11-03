import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ArrowKeyDropdownNavigation extends StatelessWidget {
  const ArrowKeyDropdownNavigation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleKeyEvent,
      child: child,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (direction == 0) return KeyEventResult.ignored;

    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext is! Element) return KeyEventResult.ignored;

    DropdownButton<dynamic>? focusedDropdown;
    focusContext.visitAncestorElements((element) {
      final currentWidget = element.widget;
      if (currentWidget is DropdownButton<dynamic>) {
        focusedDropdown = currentWidget;
        return false;
      }
      return true;
    });
    final dropdown = focusedDropdown;
    return dropdown != null && _changeDropdownValue(dropdown, direction)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  bool _changeDropdownValue(DropdownButton<dynamic> dropdown, int direction) {
    final items = dropdown.items;
    final Function? onChanged = (dropdown as dynamic).onChanged;
    if (items == null || items.length < 2 || onChanged == null) return false;

    final enabledItems = items.where((item) => item.enabled).toList();
    if (enabledItems.length < 2) return false;

    final selectedIndex = enabledItems.indexWhere(
      (item) => item.value == dropdown.value,
    );
    final nextIndex = selectedIndex < 0
        ? direction > 0
              ? 0
              : enabledItems.length - 1
        : (selectedIndex + direction + enabledItems.length) %
              enabledItems.length;
    Function.apply(onChanged, [enabledItems[nextIndex].value]);
    return true;
  }
}
