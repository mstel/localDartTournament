import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

/// Optional settings with a stable disclosure state and isolated scroll storage.
class SportSettingsSection extends StatefulWidget {
  const SportSettingsSection({
    super.key,
    required this.title,
    required this.summary,
    required this.children,
    this.icon = Icons.tune_outlined,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
  });

  final String title;
  final String summary;
  final List<Widget> children;
  final IconData icon;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<SportSettingsSection> createState() => SportSettingsSectionState();
}

class SportSettingsSectionState extends State<SportSettingsSection>
    with AutomaticKeepAliveClientMixin {
  final _storage = PageStorageBucket();
  final _controller = ExpansibleController();

  void expand() => _controller.expand();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        controller: _controller,
        maintainState: true,
        initiallyExpanded: widget.initiallyExpanded,
        onExpansionChanged: widget.onExpansionChanged,
        leading: Icon(
          widget.icon,
          color: appAccentColor(context),
        ),
        title: Text(widget.title),
        subtitle: Text(widget.summary),
        childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageStorage(
            bucket: _storage,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  widget.children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
