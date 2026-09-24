import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';

class UserLookupResult {
  const UserLookupResult({
    required this.exists,
    this.nickname = '',
    this.id = '',
    this.status = 'none', // 'none', 'self', 'pending', 'accepted', 'declined', 'incoming'
    this.error,
  });

  final bool exists;
  final String nickname;
  final String id;
  final String status;
  final String? error;
}

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
    this.apiProvider,
    this.onTrackAccepted,
  });

  final String? Function() getCurrentAccount;
  final SyncApi? Function()? apiProvider;
  final Future<void> Function(Map<String, dynamic> track)? onTrackAccepted;

  String? lastActionMessage;
  bool _isSyncing = false;

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

  /// Looks up whether a user with given nickname exists
  Future<UserLookupResult> lookupNickname(String nickname) async {
    final trimmed = nickname.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return const UserLookupResult(exists: false);
    }
    final myNick = currentNickname.toLowerCase();
    if (trimmed == myNick) {
      return UserLookupResult(
        exists: true,
        nickname: currentNickname,
        status: 'self',
      );
    }

    final api = apiProvider?.call();
    if (api == null || api.token == null) {
      // Local fallback / offline: if in friends list or requests, report status
      final isFriend = _friends.any((f) => f.nickname.toLowerCase() == trimmed);
      if (isFriend) {
        return UserLookupResult(exists: true, nickname: trimmed, status: 'accepted');
      }
      final isRequested = _requests.any(
        (r) => r.toNickname.toLowerCase() == trimmed && r.status == 'pending',
      );
      if (isRequested) {
        return UserLookupResult(exists: true, nickname: trimmed, status: 'pending');
      }
      return UserLookupResult(exists: false, nickname: trimmed);
    }

    try {
      final res = await api.request(
        'GET',
        '/friends/lookup?nickname=${Uri.encodeComponent(trimmed)}',
      );
      final exists = res['exists'] as bool? ?? false;
      return UserLookupResult(
        exists: exists,
        nickname: res['nickname'] as String? ?? trimmed,
        id: res['id'] as String? ?? '',
        status: res['status'] as String? ?? 'none',
      );
    } catch (e) {
      return UserLookupResult(
        exists: false,
        nickname: trimmed,
        error: friendlyErrorMessage(e),
      );
    }
  }

  /// Sends a friend request to a user by nick with backend validation
  Future<bool> sendFriendRequest(String targetNick) async {
    final trimmed = targetNick.trim();
    if (trimmed.isEmpty) {
      lastActionMessage = 'Введите никнейм';
      return false;
    }
    final myNick = currentNickname;
    if (trimmed.toLowerCase() == myNick.toLowerCase()) {
      lastActionMessage = 'Нельзя отправить запрос самому себе';
      return false;
    }

    // Check if already friends
    if (_friends.any((f) => f.nickname.toLowerCase() == trimmed.toLowerCase())) {
      lastActionMessage = 'Пользователь уже в вашем списке друзей';
      return false;
    }

    // Check if already requested locally
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
    if (existing.id.isNotEmpty) {
      lastActionMessage = 'Запрос уже отправлен ранее';
      return false;
    }

    final api = apiProvider?.call();
    String newId = DateTime.now().millisecondsSinceEpoch.toString();
    if (api != null && api.token != null) {
      try {
        final res = await api.request('POST', '/friends/requests', {
          'nickname': trimmed.toLowerCase(),
        });
        if (res['id'] != null) {
          newId = res['id'] as String;
        }
      } on ApiException catch (e) {
        if (e.status == 404) {
          lastActionMessage = 'Пользователь @$trimmed не найден на сервере';
          return false;
        } else if (e.status == 422) {
          lastActionMessage = 'Нельзя отправить запрос самому себе';
          return false;
        } else if (e.status == 409) {
          lastActionMessage = 'Запрос уже существует или ник не задан';
          return false;
        }
        lastActionMessage = friendlyErrorMessage(e);
        return false;
      } catch (e) {
        lastActionMessage = friendlyErrorMessage(e);
        return false;
      }
    }

    final request = FriendRequest(
      id: newId,
      fromEmail: getCurrentAccount() ?? '',
      fromNickname: myNick,
      toNickname: trimmed,
      createdAt: DateTime.now(),
    );
    _requests.add(request);
    await save();
    notifyListeners();
    lastActionMessage = 'Запрос в друзья отправлен @$trimmed';
    return true;
  }

  /// Accepts an incoming friend request
  Future<void> acceptFriendRequest(String requestId) async {
    final index = _requests.indexWhere((r) => r.id == requestId);
    final req = index >= 0 ? _requests[index] : null;

    final api = apiProvider?.call();
    if (api != null && api.token != null) {
      try {
        await api.request('POST', '/friends/requests/$requestId/accept');
      } catch (e) {
        debugPrint('Failed to accept friend request on server: $e');
      }
    }

    if (req != null) {
      req.status = 'accepted';
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
    }

    await save();
    notifyListeners();
  }

  /// Declines an incoming friend request
  Future<void> declineFriendRequest(String requestId) async {
    final api = apiProvider?.call();
    if (api != null && api.token != null) {
      try {
        await api.request('POST', '/friends/requests/$requestId/decline');
      } catch (e) {
        debugPrint('Failed to decline friend request on server: $e');
      }
    }

    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index >= 0) {
      _requests[index].status = 'declined';
      await save();
      notifyListeners();
    }
  }

  /// Removes a friend
  Future<void> removeFriend(String friendId) async {
    final api = apiProvider?.call();
    if (api != null && api.token != null) {
      try {
        await api.request('DELETE', '/friends/$friendId');
      } catch (e) {
        debugPrint('Failed to remove friend on server: $e');
      }
    }
    _friends.removeWhere(
      (f) => f.id == friendId || f.nickname.toLowerCase() == friendId.toLowerCase(),
    );
    await save();
    notifyListeners();
  }

  /// Synchronizes friends, incoming requests, and shares with the server
  Future<void> syncWithServer() async {
    final api = apiProvider?.call();
    if (api == null || api.token == null || _isSyncing) return;
    _isSyncing = true;
    try {
      final res = await api.request('GET', '/friends');
      final friendsRaw = res['friends'] as List? ?? [];
      final incomingRaw = res['incoming'] as List? ?? [];
      final outgoingRaw = res['outgoing'] as List? ?? [];
      final sharesRaw = res['shares'] as List? ?? [];

      _friends.clear();
      for (final f in friendsRaw) {
        final map = f as Map<String, dynamic>;
        _friends.add(FriendUser(
          id: map['id'] as String? ?? '',
          email: '',
          nickname: map['nickname'] as String? ?? '',
          addedAt: DateTime.now(),
        ));
      }

      // Sync incoming requests
      for (final inc in incomingRaw) {
        final map = inc as Map<String, dynamic>;
        final reqId = map['id'] as String? ?? '';
        final fromNick = map['nickname'] as String? ?? '';
        final existingIdx = _requests.indexWhere((r) => r.id == reqId);
        if (existingIdx >= 0) {
          _requests[existingIdx].status = 'pending';
        } else {
          _requests.add(FriendRequest(
            id: reqId,
            fromEmail: '',
            fromNickname: fromNick,
            toNickname: currentNickname,
            status: 'pending',
            createdAt: DateTime.now(),
          ));
        }
      }

      // Sync outgoing requests
      for (final out in outgoingRaw) {
        final map = out as Map<String, dynamic>;
        final reqId = map['id'] as String? ?? '';
        final toNick = map['nickname'] as String? ?? '';
        final existingIdx = _requests.indexWhere((r) => r.id == reqId);
        if (existingIdx < 0 && toNick.isNotEmpty) {
          _requests.add(FriendRequest(
            id: reqId,
            fromEmail: getCurrentAccount() ?? '',
            fromNickname: currentNickname,
            toNickname: toNick,
            status: 'pending',
            createdAt: DateTime.now(),
          ));
        }
      }

      // Sync incoming shares / transfers
      for (final s in sharesRaw) {
        final map = s as Map<String, dynamic>;
        final shareId = map['id'] as String? ?? '';
        final fromNick = map['nickname'] as String? ?? '';
        final existingIdx = _transfers.indexWhere((t) => t.id == shareId);
        if (existingIdx >= 0) {
          _transfers[existingIdx].status = 'pending_approval';
        } else {
          _transfers.add(TrackTransfer(
            id: shareId,
            fromNickname: fromNick,
            toNickname: currentNickname,
            track: {
              'id': map['track_id'] ?? shareId,
              'title': map['title'] ?? '',
              'artist': map['artist'] ?? '',
              'provider': map['provider'] ?? 'local',
              'source_id': map['source_id'] ?? '',
            },
            status: 'pending_approval',
            createdAt: DateTime.now(),
          ));
        }
      }

      await save();
      notifyListeners();
    } catch (e) {
      debugPrint('FriendsService.syncWithServer error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Handles real-time friend notifications received via WebSocket
  Future<void> handleRealtimeEvent(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    if (type == 'friend_request') {
      final reqId = data['request_id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString();
      final fromNick = data['from_nickname'] as String? ?? '';
      final toNick = data['to_nickname'] as String? ?? currentNickname;
      if (fromNick.isNotEmpty) {
        final existing = _requests.indexWhere((r) => r.id == reqId);
        if (existing < 0) {
          _requests.add(FriendRequest(
            id: reqId,
            fromEmail: '',
            fromNickname: fromNick,
            toNickname: toNick,
            status: 'pending',
            createdAt: DateTime.now(),
          ));
          await save();
          notifyListeners();
        }
      }
      unawaited(syncWithServer());
    } else if (type == 'friend_accepted' ||
        type == 'friend_declined' ||
        type == 'friend_removed') {
      await syncWithServer();
    } else if (type == 'track_share') {
      final shareId = data['share_id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString();
      final fromNick = data['from_nickname'] as String? ?? '';
      if (fromNick.isNotEmpty) {
        final existing = _transfers.indexWhere((t) => t.id == shareId);
        if (existing < 0) {
          _transfers.add(TrackTransfer(
            id: shareId,
            fromNickname: fromNick,
            toNickname: currentNickname,
            track: {
              'id': data['source_track_id'] ?? shareId,
              'title': data['title'] ?? '',
              'artist': data['artist'] ?? '',
              'provider': data['provider'] ?? 'local',
              'source_id': data['source_id'] ?? '',
            },
            status: 'pending_approval',
            createdAt: DateTime.now(),
          ));
          await save();
          notifyListeners();
        }
      }
      unawaited(syncWithServer());
    }
  }

  /// Proposes a track to a friend (transfers only with recipient's permission)
  Future<TrackTransfer> proposeTrackToFriend({
    required String toNickname,
    required Map<String, dynamic> track,
  }) async {
    final api = apiProvider?.call();
    String transferId = DateTime.now().millisecondsSinceEpoch.toString();
    if (api != null && api.token != null && track['id'] != null) {
      try {
        final res = await api.request(
          'POST',
          '/friends/${Uri.encodeComponent(toNickname)}/shares',
          {'track_id': track['id']},
        );
        if (res['id'] != null) {
          transferId = res['id'] as String;
        }
      } catch (e) {
        debugPrint('Failed to share track on server: $e');
      }
    }

    final transfer = TrackTransfer(
      id: transferId,
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

    final api = apiProvider?.call();
    if (api != null && api.token != null) {
      try {
        await api.request('POST', '/friends/shares/$transferId/accept');
      } catch (e) {
        debugPrint('Failed to accept track transfer on server: $e');
      }
    }

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
