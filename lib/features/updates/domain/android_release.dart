import 'update_platform.dart';

class AndroidRelease {
  const AndroidRelease({
    required this.version,
    required this.build,
    required this.url,
    required this.sha256,
    required this.size,
    required this.notes,
    this.isPrerelease = false,
    this.platform = UpdatePlatform.android,
  });
  static const repository = String.fromEnvironment(
    'GITHUB_RELEASE_REPOSITORY',
    defaultValue: 'mstel/localDartTournament',
  );
  final String version;
  final int build;
  final Uri url;
  final String sha256;
  final int size;
  final String notes;
  final bool isPrerelease;
  final UpdatePlatform platform;

  static AndroidRelease? fromGitHub(
    Map<String, dynamic> json, {
    bool includePrereleases = false,
    UpdatePlatform platform = UpdatePlatform.android,
  }) {
    if (json['draft'] != false ||
        (json['prerelease'] != false &&
            !(includePrereleases && json['prerelease'] == true))) {
      return null;
    }
    final tag = RegExp(
      r'^v(\d+\.\d+\.\d+)\+(\d+)$',
    ).firstMatch(json['tag_name'] as String? ?? '');
    if (tag == null) return null;
    final build = int.tryParse(tag[2]!);
    if (build == null || build < 1 || build > 2100000000) return null;
    final matches = (json['assets'] as List? ?? [])
        .whereType<Map>()
        .where(
          (asset) =>
              asset['name'] == platform.assetName &&
              asset['state'] == 'uploaded',
        )
        .toList();
    if (matches.length != 1) return null;
    final asset = matches.single;
    final uri = Uri.tryParse(asset['browser_download_url'] as String? ?? '');
    final digest = asset['digest'] as String? ?? '';
    final size = asset['size'];
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.startsWith('/$repository/releases/download/') ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest) ||
        size is! int ||
        size < 1 ||
        size > (platform == UpdatePlatform.android ? 300 : 800) * 1024 * 1024) {
      return null;
    }
    return AndroidRelease(
      version: tag[1]!,
      build: build,
      url: uri,
      sha256: digest.substring(7),
      size: size,
      notes: json['body'] as String? ?? '',
      isPrerelease: json['prerelease'] == true,
      platform: platform,
    );
  }

  static AndroidRelease? newest(
    List<dynamic> releases,
    int installedBuild, {
    bool includePrereleases = false,
    UpdatePlatform platform = UpdatePlatform.android,
  }) {
    final candidates =
        releases
            .whereType<Map<String, dynamic>>()
            .map(
              (json) => fromGitHub(
                json,
                includePrereleases: includePrereleases,
                platform: platform,
              ),
            )
            .whereType<AndroidRelease>()
            .where((r) => r.build > installedBuild)
            .toList()
          ..sort((a, b) => b.build.compareTo(a.build));
    return candidates.isEmpty ? null : candidates.first;
  }
}
