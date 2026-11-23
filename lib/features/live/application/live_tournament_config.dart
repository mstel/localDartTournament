/// Stable public entry point for spectators.
///
/// The channel is deliberately fixed: the QR code stays valid across events
/// and the app only replaces the small JSON document behind this page.
class LiveTournamentConfig {
  const LiveTournamentConfig._();

  static const channel = 'verein-live';
  static const bucket = 'live-tournament';
  static const viewerObject = '$channel/index.html';
  static const payloadObject = '$channel/latest.json';

  static const projectUrl = 'https://rbcsrqisbuutnnxpmcvp.supabase.co';
  static const viewerUrl =
      '$projectUrl/storage/v1/object/public/$bucket/$viewerObject'
      '?channel=$channel';
  static const payloadUrl =
      '$projectUrl/storage/v1/object/public/$bucket/$payloadObject';
}
