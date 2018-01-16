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

  test("includes the message's metadata", () async {
    client = await runAndConnect(main: r"""
      var port = new ReceivePort();
      port.sendPort.send("hi!");
      debugger();
    """);

    var isolate = await (await client.getVM()).isolates.first.load();
    await isolate.waitUntilPaused();

    var stack = await isolate.getStack();
    expect(stack.messages, hasLength(1));
    var message = stack.messages.single;

    expect(message.index, equals(0));
    expect(message.name, isNotNull);
    expect(message.size, greaterThan(0));
    expect(message.handler, isNotNull);
    expect(message.location, isNotNull);

    var value = await message.loadValue() as VMStringInstanceRef;
    expect(value.value, equals("hi!"));
  });
}
