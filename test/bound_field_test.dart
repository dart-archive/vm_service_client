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

  test("includes the field's declaration and value", () async {
    client = await runAndConnect(topLevel: r"""
      class Foo {
        final int val = 10;
      }
    """, main: r"""
      var foo = new Foo();
      debugger();
    """);

    var isolate = (await client.getVM()).isolates.first;
    await isolate.waitUntilPaused();
    var stack = await isolate.getStack();
    var foo = await stack.frames.first.variables["foo"].value.load();
    var field = foo.fields["val"];
    expect(field.declaration.name, equals("val"));
    expect(field.declaration.isFinal, isTrue);
    expect(field.value, new TypeMatcher<VMIntInstanceRef>());
    expect(field.value.value, equals(10));
    expect(field.toString(), equals("final int val = 10"));
  });
}
