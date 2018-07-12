// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:vm_service_client/vm_service_client.dart';

import 'utils.dart';

VMServiceClient client;

void main() {
  tearDown(() {
    if (client != null) client.close();
  });

  group("for an async error", () {
    var error;
    setUp(() async {
      client = await runAndConnect(main: r"""
        throw "oh no";
      """, flags: ["--pause-isolates-on-exit"]);

      var isolate = await (await client.getVM()).isolates.first.load();
      await isolate.waitUntilPaused();
      error = (await isolate.load()).error;
    });

    test("includes error metadata", () async {
      expect(error.kind, equals(VMErrorKind.unhandledException));
      expect(error.message, startsWith("Unhandled exception:\noh no"));

      expect(error.exception, new TypeMatcher<VMStringInstanceRef>());
      expect(error.exception.value, equals("oh no"));
    });

    test("parses the stack trace", () async {
      var trace = await error.getTrace();
      expect(trace.frames.first.member, equals('main'));
    });
  });

  group("for a sync error", () {
    var error;
    setUp(() async {
      client = await runAndConnect(main: r"""
        throw "oh no";
      """, flags: ["--pause-isolates-on-exit"], sync: true);

      var isolate = await (await client.getVM()).isolates.first.load();
      await isolate.waitUntilPaused();
      error = (await isolate.load()).error;
    });

    test("includes error metadata", () async {
      expect(error.kind, equals(VMErrorKind.unhandledException));
      expect(error.message, startsWith("Unhandled exception:\noh no"));

      expect(error.exception, new TypeMatcher<VMStringInstanceRef>());
      expect(error.exception.value, equals("oh no"));
    });

    test("parses the stack trace", () async {
      var trace = await error.getTrace();
      expect(trace.frames.first.member, equals('main'));
    });
  });
}
