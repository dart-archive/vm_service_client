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

  test("includes the library's metadata", () async {
    client = await runAndConnect(topLevel: r"""
      import 'dart:convert' as convert;
      export 'dart:typed_data';

      final foo = 1;

      bar() {}

      class Baz {}
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = await (await client.getVM()).isolates.first.load();
    var library = isolate.rootLibrary;

    expect(library.uri.scheme, equals("data"));
    library = await library.load();

    expect(library.isDebuggable, isTrue);

    expect(library.dependencies, contains(predicate((dependency) {
      return dependency.isImport && dependency.prefix == 'convert' &&
          dependency.target.uri.toString() == 'dart:convert';
    }, "import 'dart:convert' as convert")));

    expect(library.dependencies, contains(predicate((dependency) {
      return !dependency.isImport && dependency.prefix == null &&
          dependency.target.uri.toString() == 'dart:typed_data';
    }, "export 'dart:typed_data'")));

    expect(library.scripts, hasLength(1));
    expect(library.scripts.single.uri, equals(library.uri));
    expect(library.classes, contains("Baz"));
  });

  test("setNotDebuggable and setDebuggable control library debuggability",
      () async {
    client = await runAndConnect(main: """
      print('here'); // line 8
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = await (await client.getVM()).isolates.first.load();
    var library = await isolate.rootLibrary.load();

    await library.setNotDebuggable();
    expect((await library.load()).isDebuggable, isFalse);

    await library.setDebuggable();
    expect((await library.load()).isDebuggable, isTrue);
  });

  test("evaluate() evaluates code in the context of the library", () async {
    var client = await runAndConnect(topLevel: r"""
      int foo(int value) => value + 12;
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = await (await client.getVM()).isolates.first.load();
    var value = await isolate.rootLibrary.evaluate("foo(6)");
    expect(value, new isInstanceOf<VMIntInstanceRef>());
    expect(value.value, equals(18));
  });
}
