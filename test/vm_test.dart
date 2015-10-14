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

  test("includes the VM's metadata", () async {
    var start = new DateTime.now();
    client = await runAndConnect();

    var vm = await client.getVM();
    expect(vm.name, equals('vm'));
    expect(start.difference(vm.startTime).inMinutes, equals(0));
  });

  test("onUpdate fires when the VM's name changes", () async {
    client = await runAndConnect();
    var vm = await client.getVM();

    expect(vm.onUpdate.first.then((updated) => updated.name),
        completion(equals('fblthp')));

    await vm.setName('fblthp');
  });

  test("setName() sets the VM's name", () async {
    client = await runAndConnect();

    var vm = await client.getVM();
    await vm.setName('fblthp');
    expect((await vm.load()).name, equals('fblthp'));
  });
}
