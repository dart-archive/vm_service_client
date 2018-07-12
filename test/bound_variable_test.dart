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

  test("includes the variable's name and value", () async {
    client = await runAndConnect(main: r"""
      var foo = 'hello!';
      debugger();
    """);

    var isolate = (await client.getVM()).isolates.first;
    await isolate.waitUntilPaused();
    var stack = await isolate.getStack();
    var variable = stack.frames.first.variables["foo"];
    expect(variable.name, equals('foo'));
    expect(variable.value, new TypeMatcher<VMStringInstanceRef>());
    expect(variable.value.value, equals('hello!'));
    expect(variable.toString(), equals('var foo = "hello!"'));
  });
}
