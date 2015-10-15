// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:test/test.dart';
import 'package:vm_service_client/vm_service_client.dart';

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
    expect(version.minor, equals(0));
  });

  test("returns the flags passed to the VM", () async {
    client = await runAndConnect();

    // TODO(nweiz): check flags we pass and verify VMFlag.modified when
    // sdk#24143 is fixed.
    var flags = await client.getFlags();
    var flag = flags.firstWhere((flag) =>
        flag.name == "optimization_counter_scale");
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
    expect(isolate.pauseEvent, isNotNull);
    expect(isolate.error, isNull);
  });
}
