// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:test/test.dart';
import 'package:vm_service_client/vm_service_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'utils.dart';

VMServiceClient client;

void main() {
  tearDown(() {
    if (client != null) client.close();
  });

  test("returns the VM service version", () async {
    client = await runAndConnect();
    var version = await client.getVersion();
    expect(version.major, equals(3));
    expect(version.minor, new TypeMatcher<int>());
  });

  test("considers the VM service version valid", () async {
    client = await runAndConnect();
    await client.validateVersion();
  });

  test("validateVersion() respects a custom timeout", () async {
    client = await runAndConnect();
    expect(client.validateVersion(timeout: Duration.zero),
        throwsA(new TypeMatcher<VMUnsupportedVersionException>()));
  });

  test("returns the flags passed to the VM", () async {
    client = await runAndConnect();

    // TODO(nweiz): check flags we pass and verify VMFlag.modified when
    // sdk#24143 is fixed.
    var flags = await client.getFlags();
    var flag =
        flags.firstWhere((flag) => flag.name == "optimization_counter_scale");
    expect(flag.value, equals("2000"));
  });

  test("onIsolateStart emits an event when an isolate starts", () async {
    client = await runAndConnect(topLevel: r"""
      void inIsolate(_) {
        new ReceivePort();
      }
    """, main: r"""
      Isolate.spawn(inIsolate, null);
    """, flags: ["--pause-isolates-on-start"]);

    scheduleMicrotask(() async {
      (await client.getVM()).isolates.last.resume();
    });

    var isolate = await (await client.onIsolateStart.first).load();
    // If [isolate] is runnable by the time this fires, this will be a
    // VMPauseStartEvent. If it's not runnable yet, it'll be a VMNoneEvent.
    expect(
        isolate.pauseEvent,
        anyOf([
          new TypeMatcher<VMPauseStartEvent>(),
          new TypeMatcher<VMNoneEvent>()
        ]));
    expect(isolate.error, isNull);

    isolate = await isolate.loadRunnable();
    expect(isolate.pauseEvent, new TypeMatcher<VMPauseStartEvent>());
    expect(isolate.error, isNull);
  });

  test("with an invalid URL", () {
    var client = new VMServiceClient.connect("ws://example.org/not-a-ws");
    expect(client.done, throwsA(new TypeMatcher<WebSocketChannelException>()));
  });
}
