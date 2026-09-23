import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FriendUser {
  FriendUser({
    required this.id,
    required this.email,
    required this.nickname,
    this.isOnline = true,
    required this.addedAt,
  });

  final String id;
  final String email;
  final String nickname;
  final bool isOnline;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'nickname': nickname,
    'isOnline': isOnline,
    'addedAt': addedAt.toIso8601String(),
  };

  factory FriendUser.fromJson(Map<String, dynamic> json) => FriendUser(
    id: json['id'] as String,
    email: json['email'] as String? ?? '',
    nickname: json['nickname'] as String,
    isOnline: json['isOnline'] as bool? ?? true,
    addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class FriendRequest {
  FriendRequest({
    required this.id,
    required this.fromEmail,
    required this.fromNickname,
    required this.toNickname,
    this.status = 'pending', // 'pending', 'accepted', 'declined'
    required this.createdAt,
  });

  final String id;
  final String fromEmail;
  final String fromNickname;
  final String toNickname;
  String status;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'fromEmail': fromEmail,
    'fromNickname': fromNickname,
    'toNickname': toNickname,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
  };

  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
    id: json['id'] as String,
    fromEmail: json['fromEmail'] as String? ?? '',
    fromNickname: json['fromNickname'] as String,
    toNickname: json['toNickname'] as String,
    status: json['status'] as String? ?? 'pending',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class TrackTransfer {
  TrackTransfer({
    required this.id,
    required this.fromNickname,
    required this.toNickname,
    required this.track,
    this.status = 'pending_approval', // 'pending_approval', 'completed', 'declined'
    required this.createdAt,
  });

  final String id;
  final String fromNickname;
  final String toNickname;
  final Map<String, dynamic> track;
  String status;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'fromNickname': fromNickname,
    'toNickname': toNickname,
    'track': track,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
  };

  factory TrackTransfer.fromJson(Map<String, dynamic> json) => TrackTransfer(
    id: json['id'] as String,
    fromNickname: json['fromNickname'] as String,
    toNickname: json['toNickname'] as String,
    track: Map<String, dynamic>.from(json['track'] as Map? ?? {}),
    status: json['status'] as String? ?? 'pending_approval',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class FriendsService extends ChangeNotifier {
  FriendsService({
    required this.getCurrentAccount,
    this.onTrackAccepted,
  });

  final String? Function() getCurrentAccount;
  final Future<void> Function(Map<String, dynamic> track)? onTrackAccepted;

  static const String _friendsKey = 'maboy_friends_list';
  static const String _requestsKey = 'maboy_friend_requests';
  static const String _transfersKey = 'maboy_track_transfers';

  final List<FriendUser> _friends = [];
  final List<FriendRequest> _requests = [];
  final List<TrackTransfer> _transfers = [];

  List<FriendUser> get friends => List.unmodifiable(_friends);
  List<FriendRequest> get requests => List.unmodifiable(_requests);
  List<TrackTransfer> get transfers => List.unmodifiable(_transfers);

  /// Nickname extraction: cleans account/email of server URL and gets prefix before '@'
  static String extractNickname(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Гость';
    var clean = raw.trim();
    // Strip server URL prefix if formatted as "https://server.domain|user@email.com"
    if (clean.contains('|')) {
      clean = clean.split('|').last.trim();
    }
    // Strip schema if formatted without pipe
    if (clean.contains('://')) {
      clean = clean.split('/').last.trim();
    }
    if (clean.contains('@')) {
      final nick = clean.split('@').first.trim();
      return nick.isNotEmpty ? nick : 'Пользователь';
    }
    return clean.isNotEmpty ? clean : 'Гость';
  }

  String get currentNickname => extractNickname(getCurrentAccount());

  /// Pending notifications check (triggers the red badge on navigation)
  bool get hasPendingNotifications {
    final myNick = currentNickname.toLowerCase();
    final hasPendingFriendRequests = _requests.any(
      (r) => r.toNickname.toLowerCase() == myNick && r.status == 'pending',
    );
    final hasPendingTransfers = _transfers.any(
      (t) => t.toNickname.toLowerCase() == myNick && t.status == 'pending_approval',
    );
    return hasPendingFriendRequests || hasPendingTransfers;
  }

  List<FriendRequest> get pendingIncomingRequests {
    final myNick = currentNickname.toLowerCase();
    return _requests
        .where((r) => r.toNickname.toLowerCase() == myNick && r.status == 'pending')
        .toList();
  }

  List<TrackTransfer> get pendingIncomingTransfers {
    final myNick = currentNickname.toLowerCase();
    return _transfers
        .where((t) => t.toNickname.toLowerCase() == myNick && t.status == 'pending_approval')
        .toList();
  }

  List<TrackTransfer> get receivedCompletedTransfers {
    final myNick = currentNickname.toLowerCase();
    return _transfers
        .where((t) => t.toNickname.toLowerCase() == myNick && t.status == 'completed')
        .toList();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final friendsRaw = prefs.getString(_friendsKey);
    if (friendsRaw != null && friendsRaw.isNotEmpty) {
      try {
        final list = (jsonDecode(friendsRaw) as List).cast<Map<String, dynamic>>();
        _friends
          ..clear()
          ..addAll(list.map(FriendUser.fromJson));
      } catch (e) {
        debugPrint('Failed to load friends: $e');
      }
    }

    final requestsRaw = prefs.getString(_requestsKey);
    if (requestsRaw != null && requestsRaw.isNotEmpty) {
      try {
        final list = (jsonDecode(requestsRaw) as List).cast<Map<String, dynamic>>();
        _requests
          ..clear()
          ..addAll(list.map(FriendRequest.fromJson));
      } catch (e) {
        debugPrint('Failed to load friend requests: $e');
      }
    }

    final transfersRaw = prefs.getString(_transfersKey);
    if (transfersRaw != null && transfersRaw.isNotEmpty) {
      try {
        final list = (jsonDecode(transfersRaw) as List).cast<Map<String, dynamic>>();
        _transfers
          ..clear()
          ..addAll(list.map(TrackTransfer.fromJson));
      } catch (e) {
        debugPrint('Failed to load track transfers: $e');
      }
    }

    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _friendsKey,
      jsonEncode(_friends.map((f) => f.toJson()).toList()),
    );
    await prefs.setString(
      _requestsKey,
      jsonEncode(_requests.map((r) => r.toJson()).toList()),
    );
    await prefs.setString(
      _transfersKey,
      jsonEncode(_transfers.map((t) => t.toJson()).toList()),
    );
  }

  /// Sends a friend request to a user by nick
  Future<bool> sendFriendRequest(String targetNick) async {
    final trimmed = targetNick.trim();
    if (trimmed.isEmpty) return false;
    final myNick = currentNickname;
    if (trimmed.toLowerCase() == myNick.toLowerCase()) return false;

    // Check if already friends
    if (_friends.any((f) => f.nickname.toLowerCase() == trimmed.toLowerCase())) {
      return false;
    }

    // Check if already requested
    final existing = _requests.firstWhere(
      (r) =>
          r.fromNickname.toLowerCase() == myNick.toLowerCase() &&
          r.toNickname.toLowerCase() == trimmed.toLowerCase() &&
          r.status == 'pending',
      orElse: () => FriendRequest(
        id: '',
        fromEmail: '',
        fromNickname: '',
        toNickname: '',
        createdAt: DateTime.now(),
      ),
    );
    if (existing.id.isNotEmpty) return false;

    final request = FriendRequest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fromEmail: getCurrentAccount() ?? '',
      fromNickname: myNick,
      toNickname: trimmed,
      createdAt: DateTime.now(),
    );
    _requests.add(request);
    await save();
    notifyListeners();
    return true;
  }

  /// Accepts an incoming friend request
  Future<void> acceptFriendRequest(String requestId) async {
    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index < 0) return;
    final req = _requests[index];
    req.status = 'accepted';

    // Add sender to friends
    if (!_friends.any((f) => f.nickname.toLowerCase() == req.fromNickname.toLowerCase())) {
      _friends.add(
        FriendUser(
          id: req.id,
          email: req.fromEmail,
          nickname: req.fromNickname,
          addedAt: DateTime.now(),
        ),
      );
    }

    await save();
    notifyListeners();
  }

  /// Declines an incoming friend request
  Future<void> declineFriendRequest(String requestId) async {
    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index < 0) return;
    _requests[index].status = 'declined';
    await save();
    notifyListeners();
  }

  /// Removes a friend
  Future<void> removeFriend(String friendId) async {
    _friends.removeWhere((f) => f.id == friendId);
    await save();
    notifyListeners();
  }

  /// Proposes a track to a friend (transfers only with recipient's permission)
  Future<TrackTransfer> proposeTrackToFriend({
    required String toNickname,
    required Map<String, dynamic> track,
  }) async {
    final transfer = TrackTransfer(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fromNickname: currentNickname,
      toNickname: toNickname,
      track: track,
      status: 'pending_approval',
      createdAt: DateTime.now(),
    );
    _transfers.add(transfer);
    await save();
    notifyListeners();
    return transfer;
  }

  /// Recipient accepts incoming track transfer
  Future<void> acceptTrackTransfer(String transferId) async {
    final index = _transfers.indexWhere((t) => t.id == transferId);
    if (index < 0) return;
    final transfer = _transfers[index];
    transfer.status = 'completed';
    await save();
    notifyListeners();

    if (onTrackAccepted != null) {
      await onTrackAccepted!(transfer.track);
    }
  }

  /// Recipient declines incoming track transfer
  Future<void> declineTrackTransfer(String transferId) async {
    final index = _transfers.indexWhere((t) => t.id == transferId);
    if (index < 0) return;
    _transfers[index].status = 'declined';
    await save();
    notifyListeners();
  }

  /// For testing/simulating incoming events between accounts
  void simulateIncomingRequest({
    required String fromEmail,
    required String fromNickname,
    required String toNickname,
  }) {
    _requests.add(
      FriendRequest(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fromEmail: fromEmail,
        fromNickname: fromNickname,
        toNickname: toNickname,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void simulateIncomingTrackTransfer({
    required String fromNickname,
    required String toNickname,
    required Map<String, dynamic> track,
  }) {
    _transfers.add(
      TrackTransfer(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fromNickname: fromNickname,
        toNickname: toNickname,
        track: track,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }
}
