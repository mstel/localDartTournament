/// Storage boundary for the spectator channel. Kept abstract so publishing can
/// be unit-tested without a Supabase client.
abstract class LiveTournamentUploader {
  String? get currentUserId;

  Future<void> uploadJson(String path, List<int> bytes);

  Future<void> uploadViewer(String path, String html);

  Future<void> deleteJson(String path);
}

class InMemoryLiveTournamentUploader implements LiveTournamentUploader {
  final json = <String, List<int>>{};
  final viewer = <String, String>{};
  final deleted = <String>[];
  int jsonUploadCount = 0;
  int viewerUploadCount = 0;

  @override
  String? currentUserId;

  @override
  Future<void> uploadJson(String path, List<int> bytes) async {
    json[path] = List<int>.unmodifiable(bytes);
    jsonUploadCount++;
  }

  @override
  Future<void> uploadViewer(String path, String html) async {
    viewer[path] = html;
    viewerUploadCount++;
  }

  @override
  Future<void> deleteJson(String path) async {
    json.remove(path);
    deleted.add(path);
  }
}
