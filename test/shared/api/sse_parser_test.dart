import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/shared/api/sse.dart';

List<SseEvent> parseAll(List<String> chunks) {
  final events = <SseEvent>[];
  final parser = SseParser(events.add);
  for (final chunk in chunks) {
    parser.add(utf8.encode(chunk));
  }
  return events;
}

void main() {
  group('SseParser', () {
    test('splits events on LF, CRLF and CR', () {
      final events = parseAll([
        'data: a\n\n',
        'data: b\r\n\r\n',
        'data: c\r\r',
      ]);

      expect(events.map((e) => e.data), ['a', 'b', 'c']);
    });

    test('treats CRLF split across chunks as one newline', () {
      final events = parseAll([
        'data: a\r',
        '\n\r',
        '\ndata: b\r\n\r\n',
      ]);

      expect(events.map((e) => e.data), ['a', 'b']);
    });

    test('joins multiple data lines with newline and defaults event name', () {
      final events = parseAll(['data: first\ndata: second\n\n']);

      expect(events.single.event, 'message');
      expect(events.single.data, 'first\nsecond');
    });

    test('ignores comments, id and retry fields', () {
      final events = parseAll([
        ': keep-alive\nid: 42\nretry: 1000\ndata: x\n\n',
      ]);

      expect(events.single.data, 'x');
    });

    test('does not dispatch a blank line without data', () {
      final events = parseAll(['\n\n: note\n\n']);

      expect(events, isEmpty);
    });

    test('dispatches empty data line', () {
      final events = parseAll(['data:\n\n']);

      expect(events.single.data, '');
    });

    test('strips only one leading space after the colon', () {
      final events = parseAll(['data:  spaced\n\n', 'data:tight\n\n']);

      expect(events.map((e) => e.data), [' spaced', 'tight']);
    });

    test('treats a line without colon as an empty field value', () {
      final events = parseAll(['data\n\n']);

      expect(events.single.data, '');
    });

    test('uses the event field as the event name', () {
      final events = parseAll(['event: ping\ndata: {}\n\n']);

      expect(events.single.event, 'ping');
      expect(events.single.data, '{}');
    });

    test('discards an event not terminated by a blank line', () {
      final events = parseAll(['data: complete\n\n', 'data: trailing']);

      expect(events.map((e) => e.data), ['complete']);
    });

    test('keeps multi-byte UTF-8 characters split across chunks', () {
      final bytes = utf8.encode('data: 你好\n\n');
      final events = <SseEvent>[];
      final parser = SseParser(events.add);

      for (var i = 0; i < bytes.length; i += 2) {
        parser.add(bytes.sublist(i, i + 2 > bytes.length ? bytes.length : i + 2));
      }

      expect(events.single.data, '你好');
    });

    test('replaces malformed UTF-8 bytes instead of throwing', () {
      final events = <SseEvent>[];
      final parser = SseParser(events.add);

      parser.add([...utf8.encode('data: '), 0xff, ...utf8.encode('x\n\n')]);

      expect(events.single.data, '�x');
    });

    test('drops a leading BOM', () {
      final events = <SseEvent>[];
      final parser = SseParser(events.add);

      parser.add([0xef]);
      parser.add([0xbb, 0xbf, ...utf8.encode('data: x\n\n')]);

      expect(events.single.data, 'x');
    });

    test('assembles a frame larger than a single chunk', () {
      final line = 'data: ${'x' * 10000}\n\n';
      final events = parseAll([line.substring(0, 500), line.substring(500)]);

      expect(events.single.data.length, 10000);
    });
  });
}
