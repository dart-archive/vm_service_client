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

  test("includes the code's metadata", () async {
    client = await runAndConnect(topLevel: r"""
      void foo() {
        print("hello!");
      }
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = await (await client.getVM()).isolates.first.loadRunnable();
    var function = (await isolate.rootLibrary.load()).functions["foo"];
    var code = (await function.load()).code;

    expect(code.name, equals("[Stub] LazyCompile"));
    expect(code.kind, equals(VMCodeKind.stub));
    expect(code.toString(), equals("[Stub] LazyCompile"));

    await (function.owner as VMLibraryRef).evaluate("foo()");
    code = (await function.load()).code;
    expect(code.name, equals("foo"));
    expect(code.kind, equals(VMCodeKind.dart));
    expect(code.toString(), equals("foo (Dart)"));
  });
}
