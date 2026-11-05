import 'package:flutter/material.dart';

class TournamentDatePickerField extends StatelessWidget {
  const TournamentDatePickerField({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  Future<void> _selectDate(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      helpText: 'Turnierdatum auswählen',
    );
    if (selected != null) {
      onChanged(DateTime(selected.year, selected.month, selected.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(context).formatMediumDate(value);
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Turnierdatum',
        border: OutlineInputBorder(),
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () => _selectDate(context),
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(date),
        ),
      ),
    );
  }
}
