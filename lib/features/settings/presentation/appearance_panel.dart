import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../../app/theme_controller.dart';
import 'package:dart_tournament_manager/shared/widgets/adaptive_content.dart';

class AppearancePanel extends StatefulWidget {
  const AppearancePanel({super.key});

  @override
  State<AppearancePanel> createState() => _AppearancePanelState();
}

class _AppearancePanelState extends State<AppearancePanel> {
  bool _selectingLogo = false;

  Future<void> _selectLogo() async {
    setState(() => _selectingLogo = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Logo', extensions: ['png', 'jpg', 'jpeg', 'webp']),
        ],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      await AppThemeController.instance.setBrandLogo(bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logo konnte nicht gespeichert werden: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _selectingLogo = false);
    }
  }

  Future<void> _restoreLogo() async {
    try {
      await AppThemeController.instance.setBrandLogo(null);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Standardlogo konnte nicht geladen werden: $error'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppThemeController.instance;
    return AdaptiveContentList(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Darstellung', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Eigenes Logo', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ValueListenableBuilder(
          valueListenable: controller.logoBytesNotifier,
          builder: (context, bytes, _) => Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (bytes != null)
                Image.memory(bytes, width: 56, height: 56, fit: BoxFit.contain)
              else
                Icon(
                  Icons.sports_score,
                  color: Theme.of(context).colorScheme.primary,
                  size: 40,
                ),
              FilledButton.icon(
                onPressed: _selectingLogo ? null : _selectLogo,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  _selectingLogo ? 'Wird geladen…' : 'Logo auswählen',
                ),
              ),
              if (bytes != null)
                OutlinedButton.icon(
                  onPressed: _restoreLogo,
                  icon: const Icon(Icons.restore),
                  label: const Text('Standardlogo wiederherstellen'),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('PNG, JPG oder WebP bis 512 KB.'),
        ),
        const SizedBox(height: 20),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: controller.themeModeNotifier,
          builder: (context, mode, _) {
            return DropdownButtonFormField<ThemeMode>(
              initialValue: mode,
              decoration: const InputDecoration(labelText: 'Design‑Modus'),
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('System'),
                ),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Hell')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dunkel')),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.setThemeMode(value);
                }
              },
            );
          },
        ),
      ],
    );
  }
}
