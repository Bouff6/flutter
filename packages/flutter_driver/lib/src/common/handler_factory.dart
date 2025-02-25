// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../driver_extension.dart';
import '../extension/wait_conditions.dart';
import 'diagnostics_tree.dart';
import 'error.dart';
import 'find.dart';
import 'frame_sync.dart';
import 'geometry.dart';
import 'gesture.dart';
import 'health.dart';
import 'layer_tree.dart';
import 'message.dart';
import 'render_tree.dart';
import 'request_data.dart';
import 'semantics.dart';
import 'text.dart';
import 'wait.dart';

/// A factory which creates [Finder]s from [SerializableFinder]s.
mixin CreateFinderFactory {
  /// Creates the flutter widget finder from [SerializableFinder].
  Finder createFinder(SerializableFinder finder) {
    final String finderType = finder.finderType;
    switch (finderType) {
      case 'ByText':
        return _createByTextFinder(finder as ByText);
      case 'ByTooltipMessage':
        return _createByTooltipMessageFinder(finder as ByTooltipMessage);
      case 'BySemanticsLabel':
        return _createBySemanticsLabelFinder(finder as BySemanticsLabel);
      case 'ByValueKey':
        return _createByValueKeyFinder(finder as ByValueKey);
      case 'ByType':
        return _createByTypeFinder(finder as ByType);
      case 'PageBack':
        return _createPageBackFinder();
      case 'Ancestor':
        return _createAncestorFinder(finder as Ancestor);
      case 'Descendant':
        return _createDescendantFinder(finder as Descendant);
      default:
        throw DriverError('Unsupported search specification type $finderType');
    }
  }

  Finder _createByTextFinder(ByText arguments) {
    return find.text(arguments.text);
  }

  Finder _createByTooltipMessageFinder(ByTooltipMessage arguments) {
    return find.byElementPredicate((Element element) {
      final Widget widget = element.widget;
      if (widget is Tooltip) {
        return widget.message == arguments.text;
      }
      return false;
    }, description: 'widget with text tooltip "${arguments.text}"');
  }

  Finder _createBySemanticsLabelFinder(BySemanticsLabel arguments) {
    return find.byElementPredicate((Element element) {
      if (element is! RenderObjectElement) {
        return false;
      }
      final String? semanticsLabel = element.renderObject.debugSemantics?.label;
      if (semanticsLabel == null) {
        return false;
      }
      final Pattern label = arguments.label;
      return label is RegExp
          ? label.hasMatch(semanticsLabel)
          : label == semanticsLabel;
    }, description: 'widget with semantic label "${arguments.label}"');
  }

  Finder _createByValueKeyFinder(ByValueKey arguments) {
    switch (arguments.keyValueType) {
      case 'int':
        return find.byKey(ValueKey<int>(arguments.keyValue as int));
      case 'String':
        return find.byKey(ValueKey<String>(arguments.keyValue as String));
      default:
        throw UnimplementedError('Unsupported ByValueKey type: ${arguments.keyValueType}');
    }
  }

  Finder _createByTypeFinder(ByType arguments) {
    return find.byElementPredicate((Element element) {
      return element.widget.runtimeType.toString() == arguments.type;
    }, description: 'widget with runtimeType "${arguments.type}"');
  }

  Finder _createPageBackFinder() {
    return find.byElementPredicate((Element element) {
      final Widget widget = element.widget;
      if (widget is Tooltip) {
        return widget.message == 'Back';
      }
      if (widget is CupertinoNavigationBarBackButton) {
        return true;
      }
      return false;
    }, description: 'Material or Cupertino back button');
  }

  Finder _createAncestorFinder(Ancestor arguments) {
    final Finder finder = find.ancestor(
      of: createFinder(arguments.of),
      matching: createFinder(arguments.matching),
      matchRoot: arguments.matchRoot,
    );
    return arguments.firstMatchOnly ? finder.first : finder;
  }

  Finder _createDescendantFinder(Descendant arguments) {
    final Finder finder = find.descendant(
      of: createFinder(arguments.of),
      matching: createFinder(arguments.matching),
      matchRoot: arguments.matchRoot,
    );
    return arguments.firstMatchOnly ? finder.first : finder;
  }
}

/// A factory for [Command] handlers.
mixin CommandHandlerFactory {
  /// With [_frameSync] enabled, Flutter Driver will wait to perform an action
  /// until there are no pending frames in the app under test.
  bool _frameSync = true;

  /// Gets [DataHandler] for result delivery.
  @protected
  DataHandler? getDataHandler() => null;

  /// Registers text input emulation.
  @protected
  void registerTextInput() {
    _testTextInput.register();
  }

  final TestTextInput _testTextInput = TestTextInput();

  /// Deserializes the finder from JSON generated by [Command.serialize] or [CommandWithTarget.serialize].
  Future<Result> handleCommand(Command command, WidgetController prober, CreateFinderFactory finderFactory) {
    switch(command.kind) {
      case 'get_health': return _getHealth(command);
      case 'get_layer_tree': return _getLayerTree(command);
      case 'get_render_tree': return _getRenderTree(command);
      case 'enter_text': return _enterText(command);
      case 'get_text': return _getText(command, finderFactory);
      case 'request_data': return _requestData(command);
      case 'scroll': return _scroll(command, prober, finderFactory);
      case 'scrollIntoView': return _scrollIntoView(command, finderFactory);
      case 'set_frame_sync': return _setFrameSync(command);
      case 'set_semantics': return _setSemantics(command);
      case 'set_text_entry_emulation': return _setTextEntryEmulation(command);
      case 'tap': return _tap(command, prober, finderFactory);
      case 'waitFor': return _waitFor(command, finderFactory);
      case 'waitForAbsent': return _waitForAbsent(command, finderFactory);
      case 'waitForTappable': return _waitForTappable(command, finderFactory);
      case 'waitForCondition': return _waitForCondition(command);
      case 'waitUntilNoTransientCallbacks': return _waitUntilNoTransientCallbacks(command);
      case 'waitUntilNoPendingFrame': return _waitUntilNoPendingFrame(command);
      case 'waitUntilFirstFrameRasterized': return _waitUntilFirstFrameRasterized(command);
      case 'get_semantics_id': return _getSemanticsId(command, finderFactory);
      case 'get_offset': return _getOffset(command, finderFactory);
      case 'get_diagnostics_tree': return _getDiagnosticsTree(command, finderFactory);
    }

    throw DriverError('Unsupported command kind ${command.kind}');
  }

  Future<Health> _getHealth(Command command) async => const Health(HealthStatus.ok);

  Future<LayerTree> _getLayerTree(Command command) async {
    return LayerTree(RendererBinding.instance.renderView.debugLayer?.toStringDeep());
  }

  Future<RenderTree> _getRenderTree(Command command) async {
    return RenderTree(RendererBinding.instance.renderView.toStringDeep());
  }

  Future<Result> _enterText(Command command) async {
    if (!_testTextInput.isRegistered) {
      throw StateError(
        'Unable to fulfill `FlutterDriver.enterText`. Text emulation is '
        'disabled. You can enable it using `FlutterDriver.setTextEntryEmulation`.',
      );
    }
    final EnterText enterTextCommand = command as EnterText;
    _testTextInput.enterText(enterTextCommand.text);
    return Result.empty;
  }

  Future<RequestDataResult> _requestData(Command command) async {
    final RequestData requestDataCommand = command as RequestData;
    final DataHandler? dataHandler = getDataHandler();
    return RequestDataResult(dataHandler == null
      ? 'No requestData Extension registered'
      : await dataHandler(requestDataCommand.message));
  }

  Future<Result> _setFrameSync(Command command) async {
    final SetFrameSync setFrameSyncCommand = command as SetFrameSync;
    _frameSync = setFrameSyncCommand.enabled;
    return Result.empty;
  }

  Future<Result> _tap(Command command, WidgetController prober, CreateFinderFactory finderFactory) async {
    final Tap tapCommand = command as Tap;
    final Finder computedFinder = await waitForElement(
      finderFactory.createFinder(tapCommand.finder).hitTestable(),
    );
    await prober.tap(computedFinder);
    return Result.empty;
  }

  Future<Result> _waitFor(Command command, CreateFinderFactory finderFactory) async {
    final WaitFor waitForCommand = command as WaitFor;
    await waitForElement(finderFactory.createFinder(waitForCommand.finder));
    return Result.empty;
  }

  Future<Result> _waitForAbsent(Command command, CreateFinderFactory finderFactory) async {
    final WaitForAbsent waitForAbsentCommand = command as WaitForAbsent;
    await waitForAbsentElement(finderFactory.createFinder(waitForAbsentCommand.finder));
    return Result.empty;
  }

  Future<Result> _waitForTappable(Command command, CreateFinderFactory finderFactory) async {
    final WaitForTappable waitForTappableCommand = command as WaitForTappable;
    await waitForElement(
      finderFactory.createFinder(waitForTappableCommand.finder).hitTestable(),
    );
    return Result.empty;
  }

  Future<Result> _waitForCondition(Command command) async {
    assert(command != null);
    final WaitForCondition waitForConditionCommand = command as WaitForCondition;
    final WaitCondition condition = deserializeCondition(waitForConditionCommand.condition);
    await condition.wait();
    return Result.empty;
  }

  @Deprecated(
    'This method has been deprecated in favor of _waitForCondition. '
    'This feature was deprecated after v1.9.3.'
  )
  Future<Result> _waitUntilNoTransientCallbacks(Command command) async {
    if (SchedulerBinding.instance.transientCallbackCount != 0)
      await _waitUntilFrame(() => SchedulerBinding.instance.transientCallbackCount == 0);
    return Result.empty;
  }

  /// Returns a future that waits until no pending frame is scheduled (frame is synced).
  ///
  /// Specifically, it checks:
  /// * Whether the count of transient callbacks is zero.
  /// * Whether there's no pending request for scheduling a new frame.
  ///
  /// We consider the frame is synced when both conditions are met.
  ///
  /// This method relies on a Flutter Driver mechanism called "frame sync",
  /// which waits for transient animations to finish. Persistent animations will
  /// cause this to wait forever.
  ///
  /// If a test needs to interact with the app while animations are running, it
  /// should avoid this method and instead disable the frame sync using
  /// `set_frame_sync` method. See [FlutterDriver.runUnsynchronized] for more
  /// details on how to do this. Note, disabling frame sync will require the
  /// test author to use some other method to avoid flakiness.
  ///
  /// This method has been deprecated in favor of [_waitForCondition].
  @Deprecated(
    'This method has been deprecated in favor of _waitForCondition. '
    'This feature was deprecated after v1.9.3.'
  )
  Future<Result> _waitUntilNoPendingFrame(Command command) async {
    await _waitUntilFrame(() {
      return SchedulerBinding.instance.transientCallbackCount == 0
          && !SchedulerBinding.instance.hasScheduledFrame;
    });
    return Result.empty;
  }

  Future<GetSemanticsIdResult> _getSemanticsId(Command command, CreateFinderFactory finderFactory) async {
    final GetSemanticsId semanticsCommand = command as GetSemanticsId;
    final Finder target = await waitForElement(finderFactory.createFinder(semanticsCommand.finder));
    final Iterable<Element> elements = target.evaluate();
    if (elements.length > 1) {
      throw StateError('Found more than one element with the same ID: $elements');
    }
    final Element element = elements.single;
    RenderObject? renderObject = element.renderObject;
    SemanticsNode? node;
    while (renderObject != null && node == null) {
      node = renderObject.debugSemantics;
      renderObject = renderObject.parent;
    }
    if (node == null)
      throw StateError('No semantics data found');
    return GetSemanticsIdResult(node.id);
  }

  Future<GetOffsetResult> _getOffset(Command command, CreateFinderFactory finderFactory) async {
    final GetOffset getOffsetCommand = command as GetOffset;
    final Finder finder = await waitForElement(finderFactory.createFinder(getOffsetCommand.finder));
    final Element element = finder.evaluate().single;
    final RenderBox box = (element.renderObject as RenderBox?)!;
    Offset localPoint;
    switch (getOffsetCommand.offsetType) {
      case OffsetType.topLeft:
        localPoint = Offset.zero;
        break;
      case OffsetType.topRight:
        localPoint = box.size.topRight(Offset.zero);
        break;
      case OffsetType.bottomLeft:
        localPoint = box.size.bottomLeft(Offset.zero);
        break;
      case OffsetType.bottomRight:
        localPoint = box.size.bottomRight(Offset.zero);
        break;
      case OffsetType.center:
        localPoint = box.size.center(Offset.zero);
        break;
    }
    final Offset globalPoint = box.localToGlobal(localPoint);
    return GetOffsetResult(dx: globalPoint.dx, dy: globalPoint.dy);
  }

  Future<DiagnosticsTreeResult> _getDiagnosticsTree(Command command, CreateFinderFactory finderFactory) async {
    final GetDiagnosticsTree diagnosticsCommand = command as GetDiagnosticsTree;
    final Finder finder = await waitForElement(finderFactory.createFinder(diagnosticsCommand.finder));
    final Element element = finder.evaluate().single;
    DiagnosticsNode diagnosticsNode;
    switch (diagnosticsCommand.diagnosticsType) {
      case DiagnosticsType.renderObject:
        diagnosticsNode = element.renderObject!.toDiagnosticsNode();
        break;
      case DiagnosticsType.widget:
        diagnosticsNode = element.toDiagnosticsNode();
        break;
    }
    return DiagnosticsTreeResult(diagnosticsNode.toJsonMap(DiagnosticsSerializationDelegate(
      subtreeDepth: diagnosticsCommand.subtreeDepth,
      includeProperties: diagnosticsCommand.includeProperties,
    )));
  }

  Future<Result> _scroll(Command command, WidgetController prober, CreateFinderFactory finderFactory) async {
    final Scroll scrollCommand = command as Scroll;
    final Finder target = await waitForElement(finderFactory.createFinder(scrollCommand.finder));
    final int totalMoves = scrollCommand.duration.inMicroseconds * scrollCommand.frequency ~/ Duration.microsecondsPerSecond;
    final Offset delta = Offset(scrollCommand.dx, scrollCommand.dy) / totalMoves.toDouble();
    final Duration pause = scrollCommand.duration ~/ totalMoves;
    final Offset startLocation = prober.getCenter(target);
    Offset currentLocation = startLocation;
    final TestPointer pointer = TestPointer();
    prober.binding.handlePointerEvent(pointer.down(startLocation));
    await Future<void>.value(); // so that down and move don't happen in the same microtask
    for (int moves = 0; moves < totalMoves; moves += 1) {
      currentLocation = currentLocation + delta;
      prober.binding.handlePointerEvent(pointer.move(currentLocation));
      await Future<void>.delayed(pause);
    }
    prober.binding.handlePointerEvent(pointer.up());

    return Result.empty;
  }

  Future<Result> _scrollIntoView(Command command, CreateFinderFactory finderFactory) async {
    final ScrollIntoView scrollIntoViewCommand = command as ScrollIntoView;
    final Finder target = await waitForElement(finderFactory.createFinder(scrollIntoViewCommand.finder));
    await Scrollable.ensureVisible(target.evaluate().single, duration: const Duration(milliseconds: 100), alignment: scrollIntoViewCommand.alignment);
    return Result.empty;
  }

  Future<GetTextResult> _getText(Command command, CreateFinderFactory finderFactory) async {
    final GetText getTextCommand = command as GetText;
    final Finder target = await waitForElement(finderFactory.createFinder(getTextCommand.finder));

    final Widget widget = target.evaluate().single.widget;
    String? text;

    if (widget.runtimeType == Text) {
      text = (widget as Text).data;
    } else if (widget.runtimeType == RichText) {
      final RichText richText = widget as RichText;
      text = richText.text.toPlainText(
        includeSemanticsLabels: false,
        includePlaceholders: false,
      );
    } else if (widget.runtimeType == TextField) {
      text = (widget as TextField).controller?.text;
    } else if (widget.runtimeType == TextFormField) {
      text = (widget as TextFormField).controller?.text;
    } else if (widget.runtimeType == EditableText) {
      text = (widget as EditableText).controller.text;
    }

    if (text == null) {
      throw UnsupportedError('Type ${widget.runtimeType} is currently not supported by getText');
    }

    return GetTextResult(text);
  }

  Future<Result> _setTextEntryEmulation(Command command) async {
    final SetTextEntryEmulation setTextEntryEmulationCommand = command as SetTextEntryEmulation;
    if (setTextEntryEmulationCommand.enabled) {
      _testTextInput.register();
    } else {
      _testTextInput.unregister();
    }
    return Result.empty;
  }

  SemanticsHandle? _semantics;
  bool get _semanticsIsEnabled => RendererBinding.instance.pipelineOwner.semanticsOwner != null;

  Future<SetSemanticsResult> _setSemantics(Command command) async {
    final SetSemantics setSemanticsCommand = command as SetSemantics;
    final bool semanticsWasEnabled = _semanticsIsEnabled;
    if (setSemanticsCommand.enabled && _semantics == null) {
      _semantics = RendererBinding.instance.pipelineOwner.ensureSemantics();
      if (!semanticsWasEnabled) {
        // wait for the first frame where semantics is enabled.
        final Completer<void> completer = Completer<void>();
        SchedulerBinding.instance.addPostFrameCallback((Duration d) {
          completer.complete();
        });
        await completer.future;
      }
    } else if (!setSemanticsCommand.enabled && _semantics != null) {
      _semantics!.dispose();
      _semantics = null;
    }
    return SetSemanticsResult(semanticsWasEnabled != _semanticsIsEnabled);
  }

  // This can be used to wait for the first frame being rasterized during app launch.
  @Deprecated(
    'This method has been deprecated in favor of _waitForCondition. '
    'This feature was deprecated after v1.9.3.'
  )
  Future<Result> _waitUntilFirstFrameRasterized(Command command) async {
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    return Result.empty;
  }

  /// Runs `finder` repeatedly until it finds one or more [Element]s.
  Future<Finder> waitForElement(Finder finder) async {
    if (_frameSync)
      await _waitUntilFrame(() => SchedulerBinding.instance.transientCallbackCount == 0);

    await _waitUntilFrame(() => finder.evaluate().isNotEmpty);

    if (_frameSync)
      await _waitUntilFrame(() => SchedulerBinding.instance.transientCallbackCount == 0);

    return finder;
  }

  /// Runs `finder` repeatedly until it finds zero [Element]s.
  Future<Finder> waitForAbsentElement(Finder finder) async {
    if (_frameSync)
      await _waitUntilFrame(() => SchedulerBinding.instance.transientCallbackCount == 0);

    await _waitUntilFrame(() => finder.evaluate().isEmpty);

    if (_frameSync)
      await _waitUntilFrame(() => SchedulerBinding.instance.transientCallbackCount == 0);

    return finder;
  }

  // Waits until at the end of a frame the provided [condition] is [true].
  Future<void> _waitUntilFrame(bool Function() condition, [ Completer<void>? completer ]) {
    completer ??= Completer<void>();
    if (!condition()) {
      SchedulerBinding.instance.addPostFrameCallback((Duration timestamp) {
        _waitUntilFrame(condition, completer);
      });
    } else {
      completer.complete();
    }
    return completer.future;
  }
}
