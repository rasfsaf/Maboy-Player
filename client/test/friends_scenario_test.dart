import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maboy/src/app_controller.dart';
import 'package:maboy/src/design_system.dart';
import 'package:maboy/src/home.dart';
import 'package:maboy/src/pages/friends_page.dart';
import 'package:maboy/src/services/friends_service.dart';
import 'package:maboy/src/widgets/player_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Friends Scenario & Gateway Track Transfer Real Test', () {
    test('Nicknames are correctly derived from email up to @', () {
      expect(FriendsService.extractNickname('alex@maboy.org'), 'alex');
      expect(FriendsService.extractNickname('beatmaker_99@gmail.com'), 'beatmaker_99');
      expect(FriendsService.extractNickname('john.doe@corporate.co.uk'), 'john.doe');
      expect(FriendsService.extractNickname('https://maboy.dofic.site|tankisto237@gmail.com'), 'tankisto237');
      expect(FriendsService.extractNickname('http://192.168.1.50:8080|dj_super@yandex.ru'), 'dj_super');
      expect(FriendsService.extractNickname('single_nick'), 'single_nick');
      expect(FriendsService.extractNickname(''), 'Гость');
      expect(FriendsService.extractNickname(null), 'Гость');
    });

    test('Friend request and acceptance flow between accounts', () async {
      // User Alice
      final aliceController = AppController();
      addTearDown(aliceController.dispose);
      aliceController.account = 'https://maboy.dofic.site|alice@maboy.local';

      // User Bob
      final bobController = AppController();
      addTearDown(bobController.dispose);
      bobController.account = 'https://maboy.dofic.site|bob@maboy.local';

      expect(aliceController.userNickname, 'alice');
      expect(aliceController.userEmail, 'alice@maboy.local');
      expect(bobController.userNickname, 'bob');
      expect(bobController.userEmail, 'bob@maboy.local');

      // Alice sends friend request to Bob by nick
      final sent = await aliceController.friendsService.sendFriendRequest('bob');
      expect(sent, isTrue);

      // Simulate Bob receiving the request over gateway/sync
      bobController.friendsService.simulateIncomingRequest(
        fromEmail: 'alice@maboy.local',
        fromNickname: 'alice',
        toNickname: 'bob',
      );

      // Bob now has a pending notification -> red badge is active!
      expect(bobController.hasPendingFriendNotifications, isTrue);
      expect(bobController.friendsService.pendingIncomingRequests.length, 1);
      final incomingReq = bobController.friendsService.pendingIncomingRequests.first;
      expect(incomingReq.fromNickname, 'alice');

      // Bob accepts friend request
      await bobController.friendsService.acceptFriendRequest(incomingReq.id);

      // Pending notification is resolved -> red badge turns off!
      expect(bobController.hasPendingFriendNotifications, isFalse);
      expect(bobController.friendsService.friends.length, 1);
      expect(bobController.friendsService.friends.first.nickname, 'alice');
    });

    test('Track transfer strictly requires recipient permission before receiving', () async {
      // Alice account
      final alice = AppController();
      addTearDown(alice.dispose);
      alice.account = 'alice@maboy.local';

      // Bob account
      final bob = AppController();
      addTearDown(bob.dispose);
      bob.account = 'bob@maboy.local';

      final sampleTrack = {
        'id': 'track-synthwave-101',
        'title': 'Neon Nights',
        'artist': 'Synth Master',
        'provider': 'local',
        'source_id': 's123',
      };

      // Alice initiates a track proposal for Bob
      await alice.friendsService.proposeTrackToFriend(
        toNickname: 'bob',
        track: sampleTrack,
      );

      // Simulate Bob receiving the incoming track proposal on gateway
      bob.friendsService.simulateIncomingTrackTransfer(
        fromNickname: 'alice',
        toNickname: 'bob',
        track: sampleTrack,
      );

      // 1. Before approval: track must NOT be in Bob's library yet!
      expect(bob.tracks.any((t) => t['id'] == 'track-synthwave-101'), isFalse);
      // 2. Notification badge is lit up red
      expect(bob.hasPendingFriendNotifications, isTrue);
      expect(bob.friendsService.pendingIncomingTransfers.length, 1);

      final transfer = bob.friendsService.pendingIncomingTransfers.first;
      expect(transfer.track['title'], 'Neon Nights');
      expect(transfer.fromNickname, 'alice');

      // 3. Recipient grants permission: "Разрешить и получить"
      await bob.friendsService.acceptTrackTransfer(transfer.id);

      // 4. After approval: Track is successfully added to Bob's library and notification clears
      expect(bob.hasPendingFriendNotifications, isFalse);
      expect(bob.tracks.any((t) => t['id'] == 'track-synthwave-101'), isTrue);
      expect(bob.friendsService.receivedCompletedTransfers.length, 1);
      expect(bob.friendsService.receivedCompletedTransfers.first.track['title'], 'Neon Nights');
    });

    testWidgets('FriendsPage renders isolated UI, search, and confirmation actions', (tester) async {
      final controller = AppController();
      addTearDown(controller.dispose);
      controller.account = 'dmitry@maboy.ru';

      // Simulate an incoming track transfer waiting for confirmation
      controller.friendsService.simulateIncomingTrackTransfer(
        fromNickname: 'katya',
        toNickname: 'dmitry',
        track: {
          'id': 'track-rock',
          'title': 'Guitar Solo',
          'artist': 'Rock Star',
          'provider': 'local',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildMaboyTheme(),
          home: Scaffold(
            body: FriendsPage(controller: controller),
          ),
        ),
      );

      // Check nick badge
      expect(find.text('@dmitry'), findsOneWidget);
      expect(find.text('Ваш ник'), findsOneWidget);

      // Check pending confirmation card
      expect(find.text('Требуется ваше подтверждение'), findsOneWidget);
      expect(find.textContaining('katya хочет передать вам трек по шлюзу:'), findsOneWidget);
      expect(find.text('Guitar Solo'), findsOneWidget);
      expect(find.text('Разрешить и получить'), findsOneWidget);
      expect(find.text('Отклонить'), findsOneWidget);

      // Click "Разрешить и получить"
      await tester.tap(find.text('Разрешить и получить'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      // Track must be received and added to library
      expect(controller.tracks.any((t) => t['id'] == 'track-rock'), isTrue);
      expect(controller.hasPendingFriendNotifications, isFalse);
      expect(find.text('Требуется ваше подтверждение'), findsNothing);
    });

    testWidgets('Navigation bar displays red badge on Friends when notification is pending', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final controller = AppController();
      addTearDown(controller.dispose);
      controller.account = 'listener@maboy.io';
      controller.token = 'valid-token';

      await tester.pumpWidget(
        MaterialApp(
          theme: buildMaboyTheme(),
          home: Scaffold(
            body: HomePage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no pending notifications
      expect(controller.hasPendingFriendNotifications, isFalse);
      expect(find.text('Друзья'), findsWidgets);

      // Simulate an incoming friend request
      controller.friendsService.simulateIncomingRequest(
        fromEmail: 'friend@maboy.io',
        fromNickname: 'friend',
        toNickname: 'listener',
      );
      await tester.pumpAndSettle();

      // Badge must be active
      expect(controller.hasPendingFriendNotifications, isTrue);

      // Navigate to Friends tab
      await tester.tap(find.text('Друзья').first);
      await tester.pumpAndSettle();

      // Find incoming request card in FriendsPage
      expect(find.text('Запрос в друзья от @friend'), findsOneWidget);
      expect(find.text('Принять'), findsOneWidget);

      // Accept request
      await tester.tap(find.text('Принять'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      // Badge is cleared
      expect(controller.hasPendingFriendNotifications, isFalse);
    });

    testWidgets('Desktop PlayerSheet keeps player pinned on left with synced queue on right', (tester) async {
      tester.view.physicalSize = const Size(1300, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final controller = AppController();
      addTearDown(controller.dispose);

      controller.tracks.addAll([
        {'id': 't1', 'title': 'Alpha Song', 'artist': 'Artist A'},
        {'id': 't2', 'title': 'Beta Song', 'artist': 'Artist B'},
        {'id': 't3', 'title': 'Gamma Song', 'artist': 'Artist C'},
      ]);

      // Set synchronized queue items (identical to device-to-device queue on 1 account)
      await controller.setDeviceQueue([
        {'id': 'q1', 'track_id': 't2'},
        {'id': 'q2', 'track_id': 't3'},
      ]);

      await controller.playTrack(controller.tracks.first);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildMaboyTheme(),
          home: Scaffold(
            body: PlayerSheet(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Player controls visible
      expect(find.text('Alpha Song'), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous), findsOneWidget);
      expect(find.byIcon(Icons.skip_next), findsOneWidget);
      expect(find.byIcon(Icons.shuffle), findsWidgets);

      // Synchronized device queue visible in PlayerSheet
      expect(find.text('Очередь воспроизведения'), findsOneWidget);
      expect(find.text('Beta Song'), findsOneWidget);
      expect(find.text('Gamma Song'), findsOneWidget);
      expect(find.byIcon(Icons.clear_all), findsOneWidget);
      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(2));

      // Drag second item above first item
      final dragHandles = find.byIcon(Icons.drag_indicator);
      await tester.drag(dragHandles.last, const Offset(0, -70));
      await tester.pumpAndSettle();
      expect(controller.deviceQueue.first['id'], 'q2');

      // Clear queue button works
      await tester.tap(find.byIcon(Icons.clear_all));
      await tester.pumpAndSettle();
      expect(controller.deviceQueue.isEmpty, isTrue);
    });
  });
}
