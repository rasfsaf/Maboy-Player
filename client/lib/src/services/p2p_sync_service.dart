class P2pSyncService {
  const P2pSyncService();

  bool preferPeerForYouTube({
    required bool hasOnlinePeers,
    required String provider,
    required bool hasLocalFile,
  }) {
    return hasOnlinePeers && provider == 'youtube' && !hasLocalFile;
  }

  bool shouldRecordFailedDownload({required bool handshakeRetry}) => !handshakeRetry;

  Map<String, String> failedDownloadsAfterPeerOnline(
    Map<String, String> failedDownloads,
    bool hasOnlinePeers,
  ) {
    if (hasOnlinePeers) return <String, String>{};
    return failedDownloads;
  }
}
