import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/pages/chat/chat.dart';

class DragSelectOverlay extends StatefulWidget {
  final ChatController controller;
  final Widget child;

  const DragSelectOverlay({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<DragSelectOverlay> createState() => _DragSelectOverlayState();
}

class _DragSelectOverlayState extends State<DragSelectOverlay> {
  static const double _dragThreshold = 15.0;

  bool _pointerDown = false;
  double _startY = 0;
  double _startX = 0;
  bool _isDragSelecting = false;
  bool _cancelled = false;

  // Ordered list of visible message IDs (top-to-bottom), snapshotted at drag
  // start so layout shifts from selection changes don't cause flickering.
  List<String> _messageOrder = [];
  int _anchorIdx = -1;
  int _currentIdx = -1;
  int _initialDragDir = 0; // +1 = down, -1 = up

  // Events selected during this drag gesture
  final Set<String> _dragSelectedIds = {};

  // Events that were already selected before this drag started
  final Set<String> _preSelectedIds = {};

  ChatController get _ctrl => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: widget.child,
    );
  }

  void _onPointerDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.mouse) return;
    if (e.buttons != kPrimaryButton) return;
    _pointerDown = true;
    _startY = e.position.dy;
    _startX = e.position.dx;
    _isDragSelecting = false;
    _cancelled = false;
    _anchorIdx = -1;
    _currentIdx = -1;
    _initialDragDir = 0;
    _messageOrder = [];
    _dragSelectedIds.clear();
    _preSelectedIds.clear();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointerDown || _cancelled) return;
    if (e.kind != PointerDeviceKind.mouse) return;

    final dy = (e.position.dy - _startY).abs();
    final dx = (e.position.dx - _startX).abs();

    if (!_isDragSelecting) {
      // Horizontal movement dominant → bail, let swipe handle it
      if (dx > dy && dx > _dragThreshold / 2) {
        _cancelled = true;
        return;
      }

      if (dy < _dragThreshold) return;

      // Enter drag-select mode
      _isDragSelecting = true;

      _preSelectedIds.addAll(
        _ctrl.selectedEvents.map((ev) => ev.eventId),
      );

      // Snapshot the order of visible messages (stable for the drag duration)
      _buildMessageOrder();

      // Find and select the initial message
      final hitId = _ctrl.hitTestEventAt(_startY);
      if (hitId == null) {
        _cancelled = true;
        return;
      }
      _anchorIdx = _messageOrder.indexOf(hitId);
      if (_anchorIdx < 0) {
        _cancelled = true;
        return;
      }
      _currentIdx = _anchorIdx;
      _selectEvent(hitId);
    }

    // Find message under current pointer (live hit-test is accurate per-frame)
    final hitId = _ctrl.hitTestEventAt(e.position.dy);
    if (hitId == null) return;

    final hitIdx = _messageOrder.indexOf(hitId);
    if (hitIdx < 0) return;

    if (hitIdx == _currentIdx) return; // no change
    _currentIdx = hitIdx;

    // Determine initial direction (once)
    if (_initialDragDir == 0 && _currentIdx != _anchorIdx) {
      _initialDragDir = _currentIdx > _anchorIdx ? 1 : -1;
    }

    _updateSelection();
  }

  /// Snapshot visible message IDs sorted by screen Y position (top to bottom).
  void _buildMessageOrder() {
    final entries = <(String id, double y)>[];
    for (final entry in _ctrl.messageKeys.entries) {
      final renderObj = entry.value.currentContext?.findRenderObject();
      if (renderObj is RenderBox && renderObj.attached) {
        final topLeft = renderObj.localToGlobal(Offset.zero);
        entries.add((entry.key, topLeft.dy + renderObj.size.height / 2));
      }
    }
    entries.sort((a, b) => a.$2.compareTo(b.$2));
    _messageOrder = entries.map((e) => e.$1).toList();
  }

  void _updateSelection() {
    if (_anchorIdx < 0 || _currentIdx < 0) return;

    final lo = min(_anchorIdx, _currentIdx);
    final hi = max(_anchorIdx, _currentIdx);

    // When user reverses past the anchor, exclude the anchor message
    final reversed = _initialDragDir != 0 &&
        ((_initialDragDir > 0 && _currentIdx < _anchorIdx) ||
            (_initialDragDir < 0 && _currentIdx > _anchorIdx));

    final inRange = <String>{};
    for (var i = lo; i <= hi; i++) {
      if (reversed && i == _anchorIdx) continue;
      inRange.add(_messageOrder[i]);
    }

    // Select events newly in range
    for (final id in inRange) {
      if (!_dragSelectedIds.contains(id) && !_preSelectedIds.contains(id)) {
        _selectEvent(id);
      }
    }

    // Deselect events no longer in range
    final toRemove = <String>[];
    for (final id in _dragSelectedIds) {
      if (!inRange.contains(id)) {
        final event = _ctrl.eventById(id);
        if (event != null &&
            _ctrl.selectedEvents.any((e) => e.eventId == id)) {
          _ctrl.onSelectMessage(event); // toggle off
        }
        toRemove.add(id);
      }
    }
    _dragSelectedIds.removeAll(toRemove);
  }

  void _onPointerUp(PointerEvent e) {
    _pointerDown = false;
    _isDragSelecting = false;
  }

  void _selectEvent(String eventId) {
    if (_preSelectedIds.contains(eventId)) return;
    if (_dragSelectedIds.contains(eventId)) return;

    final event = _ctrl.eventById(eventId);
    if (event == null || event.redacted) return;

    _dragSelectedIds.add(eventId);
    _ctrl.onSelectMessage(event);
  }
}
