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

      var isolate = await (await client.getVM()).isolates.first.loadRunnable();
      var functionRef = (await isolate.rootLibrary.load()).functions["foo"];

      expect(functionRef.name, equals("foo"));
      expect((functionRef.owner as VMLibraryRef).uri.scheme, equals("data"));
      expect(functionRef.isStatic, isTrue);
      expect(functionRef.isConst, isFalse);
      expect(functionRef.toString(), equals("foo"));

      var function = await functionRef.load();
      expect(function.code.kind, equals(VMCodeKind.stub));
      expect(await sourceLine(function.location), equals(2));
    });

    test("a static function", () async {
      client = await runAndConnect(topLevel: r"""
        class Foo {
          static void foo(int arg) {}
        }
      """, flags: ["--pause-isolates-on-start"]);

      var isolate = await (await client.getVM()).isolates.first.loadRunnable();
      var klass = (await isolate.rootLibrary.load()).classes["Foo"];
      var functionRef = (await klass.load()).functions["foo"];

      expect(functionRef.name, equals("foo"));
      expect((functionRef.owner as VMClassRef).name, equals("Foo"));
      expect(functionRef.isStatic, isTrue);
      expect(functionRef.isConst, isFalse);
      expect(functionRef.toString(), equals("static foo"));

      var function = await functionRef.load();
      expect(function.code.kind, equals(VMCodeKind.stub));
      expect(await sourceLine(function.location), equals(3));
    });

    test("an instance function", () async {
      client = await runAndConnect(topLevel: r"""
        class Foo {
          void foo(int arg) {}
        }
      """, flags: ["--pause-isolates-on-start"]);

      var isolate = await (await client.getVM()).isolates.first.loadRunnable();
      var klass = (await isolate.rootLibrary.load()).classes["Foo"];
      var functionRef = (await klass.load()).functions["foo"];

      expect(functionRef.name, equals("foo"));
      expect((functionRef.owner as VMClassRef).name, equals("Foo"));
      expect(functionRef.isStatic, isFalse);
      expect(functionRef.isConst, isFalse);
      expect(functionRef.toString(), equals("foo"));

      var function = await functionRef.load();
      expect(function.code.kind, equals(VMCodeKind.stub));
      expect(await sourceLine(function.location), equals(3));
    });
  });

  test("addBreakpoint() adds a breakpoint before the function", () async {
    client = await runAndConnect(topLevel: r"""
      void foo(int arg) {
        print(arg);
      }
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = await (await client.getVM()).isolates.first.loadRunnable();
    var function = (await isolate.rootLibrary.load()).functions["foo"];

    await function.addBreakpoint();
    isolate.rootLibrary.evaluate("foo(12)");
    await isolate.waitUntilPaused();

    var frame = (await isolate.getStack()).frames.first;
    expect(frame.function.name, equals("foo"));
  });
}
