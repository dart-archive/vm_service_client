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

  group("includes metadata for", () {
    test("a top-level function metadata", () async {
      client = await runAndConnect(topLevel: r"""
        void foo(int arg) {}
      """, flags: ["--pause-isolates-on-start"]);

      var isolate = await (await client.getVM()).isolates.first.load();
      var function = (await isolate.rootLibrary.load()).functions["foo"];

      expect(function.name, equals("foo"));
      expect(function.owner, new isInstanceOf<VMLibraryRef>());
      expect(function.owner.uri.scheme, equals("data"));
      expect(function.isStatic, isTrue);
      expect(function.isConst, isFalse);
      expect(function.toString(), equals("foo"));

      function = await function.load();
      expect(await sourceLine(function.location), equals(3));
    });

    test("a static function", () async {
      client = await runAndConnect(topLevel: r"""
        class Foo {
          static void foo(int arg) {}
        }
      """, flags: ["--pause-isolates-on-start"]);

      var isolate = await (await client.getVM()).isolates.first.load();
      var klass = (await isolate.rootLibrary.load()).classes["Foo"];
      var function = (await klass.load()).functions["foo"];

      expect(function.name, equals("foo"));
      expect(function.owner, new isInstanceOf<VMClassRef>());
      expect(function.owner.name, equals("Foo"));
      expect(function.isStatic, isTrue);
      expect(function.isConst, isFalse);
      expect(function.toString(), equals("static foo"));

      function = await function.load();
      expect(await sourceLine(function.location), equals(4));
    });

    test("an instance function", () async {
      client = await runAndConnect(topLevel: r"""
        class Foo {
          void foo(int arg) {}
        }
      """, flags: ["--pause-isolates-on-start"]);

      var isolate = await (await client.getVM()).isolates.first.load();
      var klass = (await isolate.rootLibrary.load()).classes["Foo"];
      var function = (await klass.load()).functions["foo"];

      expect(function.name, equals("foo"));
      expect(function.owner, new isInstanceOf<VMClassRef>());
      expect(function.owner.name, equals("Foo"));
      expect(function.isStatic, isFalse);
      expect(function.isConst, isFalse);
      expect(function.toString(), equals("foo"));

      function = await function.load();
      expect(await sourceLine(function.location), equals(4));
    });
  });

  test("addBreakpoint() adds a breakpoint before the function", () async {
    client = await runAndConnect(topLevel: r"""
      void foo(int arg) {
        print(arg);
      }
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = await (await client.getVM()).isolates.first.load();
    var function = (await isolate.rootLibrary.load()).functions["foo"];

    await function.addBreakpoint();
    isolate.rootLibrary.evaluate("foo(12)");
    await isolate.waitUntilPaused();

    var frame = (await isolate.getStack()).frames.first;
    expect(frame.function.name, equals("foo"));
  });
}
