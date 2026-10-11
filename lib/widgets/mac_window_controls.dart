import 'package:flutter/material.dart';

import '../core/motion/motion.dart';

/// The three window buttons, drawn the way macOS draws them.
///
/// They are not the platform's buttons any more — the title bar is ours — so
/// the details that make them feel native are worth keeping: the colours, the
/// 12-point circle, the tighter spacing, and the glyphs that fade in only while
/// the pointer is over the group, which is what stops a light-grey window from
/// looking like it has three unexplained dots in the corner.
class MacWindowControls extends StatefulWidget {
  const MacWindowControls({
    super.key,
    required this.onClose,
    required this.onMinimize,
    required this.onZoom,
    this.zoomIsMaximized = false,
  });

  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onZoom;

  /// Whether the window is currently maximized, so the green button can offer
  /// the right glyph and the right tooltip.
  final bool zoomIsMaximized;

  @override
  State<MacWindowControls> createState() => _MacWindowControlsState();
}

class _MacWindowControlsState extends State<MacWindowControls> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.adaptiveDuration(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Light(
            color: const Color(0xFFFF5F57),
            hovered: _hovered,
            duration: duration,
            glyph: _Glyph.close,
            tooltip: 'Close',
            onTap: widget.onClose,
          ),
          const SizedBox(width: 8),
          _Light(
            color: const Color(0xFFFEBC2E),
            hovered: _hovered,
            duration: duration,
            glyph: _Glyph.minimize,
            tooltip: 'Minimize',
            onTap: widget.onMinimize,
          ),
          const SizedBox(width: 8),
          _Light(
            color: const Color(0xFF28C840),
            hovered: _hovered,
            duration: duration,
            glyph: widget.zoomIsMaximized ? _Glyph.unzoom : _Glyph.zoom,
            tooltip: widget.zoomIsMaximized ? 'Restore' : 'Zoom',
            onTap: widget.onZoom,
          ),
        ],
      ),
    );
  }
}

enum _Glyph { close, minimize, zoom, unzoom }

class _Light extends StatelessWidget {
  const _Light({
    required this.color,
    required this.hovered,
    required this.duration,
    required this.glyph,
    required this.tooltip,
    required this.onTap,
  });

  final Color color;
  final bool hovered;
  final Duration duration;
  final _Glyph glyph;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: duration,
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
          ),
          child: AnimatedOpacity(
            duration: duration,
            opacity: hovered ? 1 : 0,
            child: Center(
              child: CustomPaint(
                size: const Size(7, 7),
                painter: _GlyphPainter(glyph),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the tiny ×, −, + and the two corner arrows inside a light.
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph);

  final _Glyph glyph;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x88000000)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    switch (glyph) {
      case _Glyph.close:
        canvas.drawLine(Offset.zero, Offset(w, h), paint);
        canvas.drawLine(Offset(w, 0), Offset(0, h), paint);
      case _Glyph.minimize:
        canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), paint);
      case _Glyph.zoom:
        canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), paint);
        canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), paint);
      case _Glyph.unzoom:
        // The two inward corner arrows of the restore state.
        canvas.drawLine(const Offset(0, 0), Offset(w / 2, h / 2), paint);
        canvas.drawLine(Offset(w, h), Offset(w / 2, h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) => oldDelegate.glyph != glyph;
}

/// A strip the window can be dragged by, double-clicked to zoom.
///
/// With the system title bar hidden there is no bar to grab, so the app has to
/// provide one. [onDrag]/[onZoom] are supplied by the window rather than this
/// widget so the shell stays testable without a real window.
class MacDragRegion extends StatelessWidget {
  const MacDragRegion({
    super.key,
    required this.onDrag,
    required this.onZoom,
    this.child,
    this.height = 38,
  });

  final VoidCallback onDrag;
  final VoidCallback onZoom;
  final Widget? child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => onDrag(),
      onDoubleTap: onZoom,
      // No width of its own: an `double.infinity` here is an infinite width in
      // an unbounded slot, and inside `NavigationRail.leading` that made the
      // whole rail infinitely wide and pushed the sidebar off the window.
      // Whoever places this decides how wide it is.
      child: SizedBox(height: height, child: child),
    );
  }
}
