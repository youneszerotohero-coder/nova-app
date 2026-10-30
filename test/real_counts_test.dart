import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/realtime/reverb_client.dart';
import 'package:nova_mobile/data/models.dart';

/// D-181: the app shows the real number of Students.
void main() {
  test('a running Live carries the Students watching now apart from those who attended', () {
    final LiveSession running = LiveSession.fromJson(<String, dynamic>{
      'id': 67, 'title': 'Live', 'status': 'live', 'attendees_count': 49, 'watching_now': 35,
    });
    expect(running.attendees, 49);
    expect(running.watchingNow, 35);

    final LiveSession ended = LiveSession.fromJson(<String, dynamic>{
      'id': 66, 'title': 'Live', 'status': 'ended', 'attendees_count': 32, 'watching_now': null,
    });
    expect(ended.attendees, 32);
    expect(ended.watchingNow, isNull);
  });

  test('presence counts Students, never Admins; a member without the flag still counts', () {
    expect(ReverbClient.isViewer(<String, dynamic>{'id': 20, 'viewer': true}), isTrue);
    expect(ReverbClient.isViewer(<String, dynamic>{'id': 1, 'viewer': false}), isFalse);
    expect(ReverbClient.isViewer(<String, dynamic>{'id': 21}), isTrue);
    expect(ReverbClient.isViewer(null), isTrue);
  });
}
