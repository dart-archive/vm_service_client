// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library vm_service_client.utils;

import 'dart:async';

/// Transforms [stream] with a [StreamTransformer] that transforms data events
/// using [handleData].
Stream transform(Stream stream, handleData(data, EventSink sink)) =>
    stream.transform(
        new StreamTransformer.fromHandlers(handleData: handleData));
