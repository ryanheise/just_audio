import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class DebugLabel extends StatelessWidget {
  final String label;
  final Widget child;

  const DebugLabel({
    Key? key,
    required this.label,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.loose,
      children: [
        Positioned(child: child),
        Positioned(
          left: 0.0,
          right: 0.0,
          bottom: 0.0,
          child: Center(
            child: Text(label),
          ),
        ),
      ],
    );
  }
}

class ValueStreamBuilder<T> extends StreamBuilderBase<T, T> {
  final T initialValue;
  final Widget Function(BuildContext context, T value) builder;

  const ValueStreamBuilder({
    Key? key,
    required Stream<T> stream,
    required this.initialValue,
    required this.builder,
  }) : super(key: key, stream: stream);

  @override
  T afterData(T current, T data) => data;

  @override
  Widget build(BuildContext context, T currentSummary) =>
      builder(context, currentSummary);

  @override
  T initial() => initialValue;
}

extension NextLoopModeExtension on LoopMode {
  LoopMode get next => LoopMode.values[(index + 1) % LoopMode.values.length];
}
