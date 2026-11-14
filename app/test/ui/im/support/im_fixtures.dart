// Scripted DS Bot fixtures for the light (IM) mode tests.
//
// Six shapes the plan asked for: three parts of history with a cursor that
// pages across them, a part divider, a Bot that is both awaiting an approval and
// working, an offline send that fails once and then succeeds, a name longer than
// any row can show, and a team with no Bots.
//
// They stand on the Bot pages' `FakeDsBotTransport`; the IM shell and timeline
// tests read the same fixtures, so the shapes stay in one place.

import 'package:dsh_client/dsh_client.dart';

import '../../../bots/support.dart';

/// The row that marks where an earlier part of the conversation starts. The
/// timeline draws it as 「更早的部分」 today and as the new light text later.
Map<String, Object?> imDividerItem({DateTime? time}) => {
  'kind': 'divider',
  'time': (time ?? todayAt(14, 0)).millisecondsSinceEpoch,
};

/// Sets one field on the Bot named [botId] in a `state` map, whichever map type
/// the fixture literal ended up with.
void setBotField(Map<String, Object?> team, String botId, String key, Object? value) {
  for (final raw in team['bots']! as List) {
    final bot = (raw as Map).cast<String, Object?>();
    if (bot['id'] == botId) bot[key] = value;
  }
}

/// Sets one field on the group named [roomId] in a `state` map.
void setRoomField(Map<String, Object?> team, String roomId, String key, Object? value) {
  for (final raw in team['rooms']! as List) {
    final room = (raw as Map).cast<String, Object?>();
    if (room['id'] == roomId) room[key] = value;
  }
}

/// Three parts of history: the first page is the current part, the cursor pages
/// back to the second and then the first, and the second part ends with a
/// divider so `loadEarlier` has a part boundary to cross.
FakeDsBotTransport threePartTransport() {
  final transport = FakeDsBotTransport();
  final base = todayAt(14, 0).millisecondsSinceEpoch;

  final firstPart = <Object?>[
    {'kind': 'user', 'text': '第一段的问题', 'time': base - 900000},
    {'kind': 'bot', 'text': '第一段的回答', 'time': base - 890000},
  ];
  final secondPart = <Object?>[
    {'kind': 'user', 'text': '第二段的问题', 'time': base - 600000},
    {'kind': 'bot', 'text': '第二段的回答', 'time': base - 590000},
    imDividerItem(time: DateTime.fromMillisecondsSinceEpoch(base - 580000)),
  ];
  final currentPart = <Object?>[
    {'kind': 'user', 'text': '当前段的问题', 'time': base - 120000},
    {'kind': 'bot', 'text': '当前段的回答', 'time': base - 110000},
  ];

  transport.handlers['chat'] = (payload) {
    final cursor = payload['cursor'];
    if (cursor == null) return {'sessionId': 'm1c', 'items': currentPart, 'cursor': {'part': 'second'}};
    if (cursor is Map && cursor['part'] == 'second') return {'sessionId': 'm1c', 'items': secondPart, 'cursor': {'part': 'first'}};
    if (cursor is Map && cursor['part'] == 'first') return {'sessionId': 'm1c', 'items': firstPart, 'cursor': null};
    return {'sessionId': 'm1c', 'items': <Object?>[], 'cursor': null};
  };

  final data = sampleTeam(working: false);
  setBotField(data, 'm1', 'parts', ['m1', 'm1-second', 'm1-first']);
  transport.handlers['state'] = (_) => data;
  return transport;
}

/// A team whose only page carries a part divider, for the row's own test.
FakeDsBotTransport dividerTransport() {
  final transport = FakeDsBotTransport();
  transport.chatItems = <Object?>[imDividerItem(), ...sampleChat()];
  return transport;
}

/// One Bot (b2) that is working and has a question waiting at the same time,
/// so the list's status priority has both states to choose from.
FakeDsBotTransport approvalAndWorkTransport() {
  final data = sampleTeam(
    working: false,
    questions: {
      'b2': {
        'id': 'q-im-1',
        'question': '这条命令可以运行吗？',
        'options': [
          {'label': '允许'},
          {'label': '这次不用'},
        ],
      },
    },
  );
  final now = DateTime.now().millisecondsSinceEpoch;
  data['activity'] = {'b2': 'tool'};
  data['work'] = {
    'bots': {
      'b2': {'since': now - 1000, 'tool': 'bash', 'note': '运行测试'},
    },
    'rooms': <String, Object?>{},
    'approvals': [
      {
        'id': 'a-im-1',
        'sessionId': 'b2',
        'botId': 'b2',
        'roomId': null,
        'tool': 'bash',
        'reason': '运行测试',
        'answerable': true,
      },
    ],
  };
  final transport = FakeDsBotTransport(team: data);
  transport.handlers['state'] = (_) => data;
  return transport;
}

/// Sends fail [failures] times with an offline error, then go through.
FakeDsBotTransport offlineSendTransport({int failures = 1}) {
  final transport = FakeDsBotTransport();
  var remaining = failures;
  transport.handlers['send'] = (_) {
    if (remaining > 0) {
      remaining -= 1;
      throw DshRemoteException('bot/offline', '连接已断开');
    }
    return true;
  };
  return transport;
}

/// A name and role longer than a row can show, plus a long message, for
/// ellipsis and overflow checks.
const longBotName = '一个名字长到任何列表行都放不下的机器人名字一个名字长到任何列表行都放不下';
const longBotRole = '负责一件非常复杂的事情的角色说明，长到两行都放不下，需要省略';
const longRoomName = '一个名字长到列表里放不下的群聊名称一个名字长到列表里放不下的群聊';
const longMessage = '这是一条很长的消息，带 emoji 😀🚀 和中英混排 mixed content，'
    '用来检查预览省略、气泡换行和最大字号下的布局是否仍然可读。';

FakeDsBotTransport longNameTransport() {
  final data = sampleTeam(working: false);
  setBotField(data, 'b2', 'name', longBotName);
  setBotField(data, 'b2', 'role', longBotRole);
  setRoomField(data, 'r1', 'name', longRoomName);
  setRoomField(data, 'r1', 'preview', longMessage);
  final transport = FakeDsBotTransport(team: data);
  transport.chatItems = <Object?>[
    {'kind': 'user', 'text': longMessage, 'time': todayAt(14, 0).millisecondsSinceEpoch},
    {'kind': 'bot', 'text': longMessage, 'time': todayAt(14, 1).millisecondsSinceEpoch},
  ];
  return transport;
}

/// A team with no Bots and no groups: the two empty states.
FakeDsBotTransport emptyTeamTransport() {
  final data = sampleTeam(working: false);
  data['bots'] = <Object?>[];
  data['rooms'] = <Object?>[];
  data['mainBotIds'] = <String>[];
  data['questions'] = <String, Object?>{};
  data['views'] = <String, Object?>{};
  final transport = FakeDsBotTransport(team: data);
  transport.chatItems = <Object?>[];
  return transport;
}
