## 0.2.0

* **Breaking change**: `new VMServiceClient()` and `new
  VMServiceClient.withoutJson()` now take a `StreamChannel` rather than a
  `Stream`/`Sink` pair.

* **Breaking change**: the static asynchronous factory
  `VMServiceClient.connect()` is now a synchronous constructor, `new
  VMServiceClient.connect()`.

## 0.1.3

* On VM service versions 3.4 and greater, `VMIsolate.pauseEvent` now returns an
  instance of `VMNoneEvent` before the isolate is runnable.

## 0.1.2+1

* Drop the dependency on the `crypto` package.

## 0.1.2

* Add `VMIsolateRef.onExtensionEvent`, which emits events posted by VM service
  extensions using `postEvent` in `dart:developer`.

* Add `VMIsolateRef.selectExtensionEvents()`, which selects events with specific
  kinds posted by VM service extensions using `postEvent` in `dart:developer`.

* Add `VMIsolateRef.onExtensionAdded`, which emits an event when a VM service
  extension registers a new RPC.

* Add `VMIsolateRef.waitForExtension()`, which returns when a given extension
  RPC is available.

* Add `VMIsolateRef.invokeExtension()`, which invokes VM service extension RPCs
  registered using `registerExtension` in `dart:developer`.

* Add `VMIsolate.extensionRpcs`, which returns the extension RPCs registered in
  a given isolate.

## 0.1.1+1

* Fix a bug where `VMPauseEvent.time` would always be reported as `null` or
  crash.

## 0.1.1

* Fix support for VM service protocol 1.0 events.

## 0.1.0

* Initial version.
