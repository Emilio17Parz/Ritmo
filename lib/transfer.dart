import 'dart:async';
import 'dart:io';

class TransferCancelled implements Exception {
  const TransferCancelled();
  @override
  String toString() => 'Cancelado';
}

/// Cancellation is independent of the network stream producing another event.
class StopSignal {
  final _cancel = Completer<void>();
  bool get cancelled => _cancel.isCompleted;
  void stop() {
    if (!cancelled) {
      _cancel.complete();
    }
  }

  Future<T> guard<T>(Future<T> operation, Duration timeout) => Future.any<T>([
    operation.timeout(timeout),
    _cancel.future.then<T>((_) => throw const TransferCancelled()),
  ]);
  void check() {
    if (cancelled) {
      throw const TransferCancelled();
    }
  }
}

Future<int> writeAudioStream({
  required Stream<List<int>> stream,
  required File destination,
  required StopSignal stop,
  required int expectedBytes,
  required void Function(int received, int expected) progress,
  Duration idleTimeout = const Duration(seconds: 25),
}) async {
  final iterator = StreamIterator<List<int>>(stream);
  RandomAccessFile? output;
  var received = 0;
  var complete = false;
  try {
    stop.check();
    output = await destination.open(mode: FileMode.write);
    while (await stop.guard(iterator.moveNext(), idleTimeout)) {
      stop.check();
      final bytes = iterator.current;
      await output.writeFrom(bytes);
      received += bytes.length;
      progress(received, expectedBytes);
    }
    stop.check();
    if (received == 0 || (expectedBytes > 0 && received != expectedBytes)) {
      throw const FileSystemException('El audio llegó incompleto.');
    }
    await output.flush();
    complete = true;
    return received;
  } finally {
    // A broken provider must not keep cancellation pending forever.
    try {
      await iterator.cancel().timeout(const Duration(seconds: 2));
    } catch (_) {}
    await output?.close();
    if (!complete && await destination.exists()) {
      await destination.delete();
    }
  }
}
