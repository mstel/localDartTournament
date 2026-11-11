import 'package:flutter/material.dart';

/// Keeps form fields mounted while secondary settings are folded away.
class ExpertSetupSection extends StatefulWidget {
  const ExpertSetupSection({
    super.key,
    required this.title,
    required this.summary,
    required this.children,
    this.initiallyExpanded = false,
    this.enabled = true,
  });
  final String title, summary;
  final List<Widget> children;
  final bool initiallyExpanded;
  final bool enabled;
  @override
  State<ExpertSetupSection> createState() => _ExpertSetupSectionState();
}

class _ExpertSetupSectionState extends State<ExpertSetupSection> {
  final _contentStorage = PageStorageBucket();
  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      key: PageStorageKey(widget.title),
      enabled: widget.enabled,
      maintainState: true,
      initiallyExpanded: widget.initiallyExpanded,
      title: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(widget.summary),
      childrenPadding: const EdgeInsets.all(16),
      children: [
        PageStorage(
          bucket: _contentStorage,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
        ),
      ],
    ),
  );
}
