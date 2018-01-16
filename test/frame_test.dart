// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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
    expect(frame.function.name, equals("<main_async_body>"));
    expect(frame.code.kind, equals(VMCodeKind.dart));
    expect(frame.variables, contains("foo"));
    expect(frame.toString(), equals("#0 in <main_async_body>"));
    expect(await sourceLine(frame.location), equals(10));
  });

  test("evaluate() evaluates code in the context of the frame", () async {
    client = await runAndConnect(main: r"""
      var foo = 'hello!';
      debugger();
    """);

    var isolate = (await client.getVM()).isolates.first;
    await isolate.waitUntilPaused();
    var frame = (await isolate.getStack()).frames.first;
    var value = await frame.evaluate("foo + ' world'") as VMStringInstanceRef;
    expect(value.value, equals("hello! world"));
  });

  test("getFrame() returns a stack_trace frame", () async {
    var client = await runAndConnect(main: r"""
      debugger();
    """);

    var isolate = (await client.getVM()).isolates.first;
    await isolate.waitUntilPaused();
    var frame = await (await isolate.getStack()).frames.first.getFrame();
    expect(frame.uri.scheme, equals('data'));
    expect(frame.line, equals(9));
    expect(frame.column, equals(0));
    expect(frame.member, equals('main.<fn>'));
  });
}
