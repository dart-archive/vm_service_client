// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:vm_service_client/vm_service_client.dart';
import 'package:test/test.dart';

import 'utils.dart';

VMServiceClient client;

void main() {
  tearDown(() {
    if (client != null) client.close();
  });

  test("includes a frame's metadata", () async {
    client = await runAndConnect(main: r"""
      var foo = 'hello!';
      debugger();
    """);

    var isolate = (await client.getVM()).isolates.first;
    await isolate.waitUntilPaused();
    var frame = (await isolate.getStack()).frames.first;
    expect(frame.index, equals(0));
    expect(frame.variables, contains("foo"));
    expect(frame.toString(), equals("#0"));
    expect(await sourceLine(frame.location), equals(11));
  });

  test("evaluate() evaluates code in the context of the frame", () async {
    client = await runAndConnect(main: r"""
      var foo = 'hello!';
      debugger();
    """);

    var isolate = (await client.getVM()).isolates.first;
    await isolate.waitUntilPaused();
    var frame = (await isolate.getStack()).frames.first;
    var value = await frame.evaluate("foo + ' world'");
    expect(value, new isInstanceOf<VMStringInstanceRef>());
    expect(value.value, equals("hello! world"));
  });
}
