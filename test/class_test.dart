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

  test("includes the class's metadata", () async {
    client = await runAndConnect(topLevel: r"""
      class Foo implements Comparable {
        final int value = 1;

        int compareTo(other) => 0;
      }

      class Bar extends Foo {}
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = await (await client.getVM()).isolates.first.loadRunnable();
    var klassRef = (await isolate.rootLibrary.load()).classes["Foo"];

    expect(klassRef.name, equals("Foo"));
    var klass = await klassRef.load();

    expect(klass.error, isNull);
    expect(klass.isAbstract, isFalse);
    expect(klass.isConst, isFalse);
    expect(klass.library.uri.scheme, equals("data"));
    expect(klass.location.script.uri.scheme, equals("data"));
    expect(klass.superclass.name, equals("Object"));
    expect(klass.interfaces.single.name, equals("Comparable"));
    expect(klass.fields, contains("value"));
    expect(klass.functions, contains("compareTo"));
    expect(klass.subclasses.single.name, equals("Bar"));
  });

  test("evaluate() evaluates code in the context of the class", () async {
    client = await runAndConnect(topLevel: r"""
      class Foo {
        static int foo(int value) => value + 12;
      }
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = await (await client.getVM()).isolates.first.loadRunnable();
    var klass = (await isolate.rootLibrary.load()).classes["Foo"];
    var value = await klass.evaluate("foo(6)") as VMIntInstanceRef;
    expect(value.value, equals(18));
  });
}
