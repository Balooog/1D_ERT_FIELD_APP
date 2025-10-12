import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../state/project_controller.dart';
import 'logging.dart';

enum HydrationStatus { cold, warming, ready, error }

@immutable
class HydrationSnapshot {
  const HydrationSnapshot({
    required this.status,
    this.error,
    this.stackTrace,
  });

  const HydrationSnapshot.cold() : this(status: HydrationStatus.cold);

  final HydrationStatus status;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isReady => status == HydrationStatus.ready;
  bool get hasError => status == HydrationStatus.error;
}

class HydrationGate {
  HydrationGate();

  final ValueNotifier<HydrationSnapshot> _snapshot =
      ValueNotifier<HydrationSnapshot>(const HydrationSnapshot.cold());
  Completer<void>? _inflight;

  ValueListenable<HydrationSnapshot> get snapshot => _snapshot;

  HydrationSnapshot get value => _snapshot.value;

  bool get isReady => value.isReady;

  Future<void> warmUp(ProjectController controller) {
    return warmUpWith(() async {
      await controller.ensureProjectLoaded();
      await controller.ensureSitesIndexed();
    });
  }

  Future<void> warmUpWith(Future<void> Function() callback) {
    if (_inflight != null) {
      return _inflight!.future;
    }
    if (value.isReady) {
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _inflight = completer;
    _snapshot.value =
        const HydrationSnapshot(status: HydrationStatus.warming);
    Future<void>(() async {
      try {
        await callback();
        _snapshot.value =
            const HydrationSnapshot(status: HydrationStatus.ready);
        LOG.i('Hydration', 'Warm-up sequence completed');
        completer.complete();
      } catch (error, stackTrace) {
        LOG.e('Hydration', 'Warm-up failed', error, stackTrace);
        _snapshot.value = HydrationSnapshot(
          status: HydrationStatus.error,
          error: error,
          stackTrace: stackTrace,
        );
        completer.completeError(error, stackTrace);
      } finally {
        _inflight = null;
      }
    });
    return completer.future;
  }

  ValueListenable<bool> watchReady() {
    return _HydrationSelector<bool>(this, (snapshot) => snapshot.isReady);
  }

  ValueListenable<T> watch<T>(T Function(HydrationSnapshot snapshot) selector) {
    return _HydrationSelector<T>(this, selector);
  }

  void dispose() {
    _snapshot.dispose();
  }
}

class _HydrationSelector<T> extends ChangeNotifier implements ValueListenable<T> {
  _HydrationSelector(this._gate, this._selector)
      : _value = _selector(_gate.value) {
    _gate._snapshot.addListener(_handleChange);
  }

  final HydrationGate _gate;
  final T Function(HydrationSnapshot snapshot) _selector;
  late T _value;

  @override
  T get value => _value;

  void _handleChange() {
    final next = _selector(_gate.value);
    if (next != _value) {
      _value = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _gate._snapshot.removeListener(_handleChange);
    super.dispose();
  }
}

class HydrationGateBuilder extends StatefulWidget {
  const HydrationGateBuilder({
    super.key,
    required this.gate,
    required this.onWarmUp,
    required this.readyBuilder,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final HydrationGate gate;
  final Future<void> Function() onWarmUp;
  final WidgetBuilder readyBuilder;
  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext context, Object error, StackTrace? stack)?
      errorBuilder;

  @override
  State<HydrationGateBuilder> createState() => _HydrationGateBuilderState();
}

class _HydrationGateBuilderState extends State<HydrationGateBuilder> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_triggerWarmup);
  }

  @override
  void didUpdateWidget(HydrationGateBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gate != widget.gate) {
      scheduleMicrotask(_triggerWarmup);
    }
  }

  Future<void> _triggerWarmup() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await widget.gate.warmUpWith(widget.onWarmUp);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HydrationSnapshot>(
      valueListenable: widget.gate.snapshot,
      builder: (context, snapshot, _) {
        switch (snapshot.status) {
          case HydrationStatus.ready:
            return widget.readyBuilder(context);
          case HydrationStatus.error:
            final builder = widget.errorBuilder;
            if (builder != null && snapshot.error != null) {
              return builder(context, snapshot.error!, snapshot.stackTrace);
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text('Failed to hydrate: ${snapshot.error}'),
              ),
            );
          case HydrationStatus.cold:
          case HydrationStatus.warming:
            final loadingBuilder = widget.loadingBuilder;
            if (loadingBuilder != null) {
              return loadingBuilder(context);
            }
            return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }
}
