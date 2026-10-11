import 'package:flutter/material.dart';

import '../../core/settings/playback_settings.dart';
import '../../core/theme/theme_engine.dart';

/// Formats a band centre frequency the way an equalizer labels it.
String formatBandFrequency(double frequency) => frequency >= 1000
    ? '${(frequency / 1000).toStringAsFixed(frequency % 1000 == 0 ? 0 : 1)}k'
    : frequency.toStringAsFixed(0);

/// The interactive equalizer: a curve you drag, one node per band.
///
/// Why a graph rather than ten sliders: an equalizer *is* a shape. Sliders make
/// you read ten numbers and hold them in your head; a curve shows you the shape
/// you are hearing, and dragging a node is the edit people actually want to
/// make.
///
/// The drag is tracked locally and [onChanged] fires once, when the gesture
/// ends. Pushing a new filter chain to libmpv on every pointer move would rebuild
/// the audio graph dozens of times a second for changes nobody can hear yet, and
/// would also fight the pointer: a rebuild mid-drag snaps the node out from
/// under the finger.
class EqGraph extends StatefulWidget {
  const EqGraph({
    super.key,
    required this.bands,
    required this.onChanged,
    this.enabled = true,
    this.minGain = -12,
    this.maxGain = 12,
    this.height = 220,
  });

  /// The bands to draw, in ascending frequency order.
  final List<EqBand> bands;

  /// Called once per gesture, with the bands as they were left.
  final ValueChanged<List<EqBand>> onChanged;

  /// When false the curve is drawn dimmed and gestures are ignored.
  final bool enabled;

  final double minGain;
  final double maxGain;
  final double height;

  @override
  State<EqGraph> createState() => _EqGraphState();
}

class _EqGraphState extends State<EqGraph> {
  late List<double> _gains = _gainsOf(widget.bands);

  /// The node under the finger, or null when no drag is in progress.
  int? _activeBand;

  static List<double> _gainsOf(List<EqBand> bands) => <double>[
    for (final band in bands) band.gain,
  ];

  @override
  void didUpdateWidget(covariant EqGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Resync from the outside only when idle, so a rebuild during a drag cannot
    // yank the node back to its stored value.
    if (_activeBand == null && !_sameGains(oldWidget.bands, widget.bands)) {
      _gains = _gainsOf(widget.bands);
    }
  }

  static bool _sameGains(List<EqBand> a, List<EqBand> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].gain != b[i].gain) return false;
    }
    return true;
  }

  void _moveTo(Offset local, Size size) {
    if (!widget.enabled || _gains.isEmpty) return;

    // Snap to the nearest band by x, so a drag anywhere on the canvas moves the
    // closest node instead of doing nothing in the gaps between them.
    final count = _gains.length;
    final slot = count == 1 ? 0.0 : (local.dx / size.width) * (count - 1);
    final index = slot.round().clamp(0, count - 1);

    final usable = size.height - EqGraphPainter.verticalPadding * 2;
    final t = usable <= 0
        ? 0.5
        : ((local.dy - EqGraphPainter.verticalPadding) / usable).clamp(
            0.0,
            1.0,
          );
    final gain = widget.maxGain - t * (widget.maxGain - widget.minGain);

    setState(() {
      _activeBand = index;
      _gains[index] = gain.clamp(widget.minGain, widget.maxGain).toDouble();
    });
  }

  void _commit() {
    if (_activeBand == null) return;
    final bands = <EqBand>[
      for (var i = 0; i < widget.bands.length; i++)
        widget.bands[i].copyWith(gain: _gains[i]),
    ];
    setState(() => _activeBand = null);
    widget.onChanged(bands);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.gandarTokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, widget.height);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (details) => _moveTo(details.localPosition, size),
          onPanUpdate: (details) => _moveTo(details.localPosition, size),
          onPanEnd: (_) => _commit(),
          onPanCancel: _commit,
          child: Semantics(
            label: 'Equalizer curve',
            value: _gains
                .map((g) => '${g > 0 ? '+' : ''}${g.toStringAsFixed(0)}')
                .join(', '),
            child: CustomPaint(
              size: size,
              painter: EqGraphPainter(
                gains: _gains,
                frequencies: <double>[
                  for (final band in widget.bands) band.frequency,
                ],
                activeBand: _activeBand,
                minGain: widget.minGain,
                maxGain: widget.maxGain,
                lineColor: widget.enabled
                    ? tokens.accentColor
                    : tokens.textSecondaryColor,
                fillColor: tokens.accentColor,
                gridColor: tokens.borderColor,
                labelColor: tokens.textSecondaryColor,
                background: tokens.surfaceElevatedColor,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints the equalizer curve.
class EqGraphPainter extends CustomPainter {
  EqGraphPainter({
    required this.gains,
    required this.frequencies,
    required this.activeBand,
    required this.minGain,
    required this.maxGain,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.labelColor,
    required this.background,
  });

  final List<double> gains;
  final List<double> frequencies;
  final int? activeBand;
  final double minGain;
  final double maxGain;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color labelColor;
  final Color background;

  /// Room above and below the travel of the curve, so a node at +12 dB is not
  /// drawn on the very edge where its label would be clipped.
  static const double verticalPadding = 22;

  double _x(int index, Size size) => gains.length <= 1
      ? size.width / 2
      : size.width * index / (gains.length - 1);

  double _y(double gain, Size size) {
    final range = maxGain - minGain;
    final usable = size.height - verticalPadding * 2;
    final t = range == 0 ? 0.5 : (maxGain - gain) / range;
    return verticalPadding + t * usable;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (gains.isEmpty) return;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      Paint()..color = background,
    );

    // Reference lines: the ends of the range and the flat 0 dB line, which is
    // the one the eye needs to judge a boost against a cut.
    for (final gain in <double>[maxGain, 0, minGain]) {
      final y = _y(gain, size);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = gridColor
          ..strokeWidth = gain == 0 ? 1.2 : 0.8,
      );
      _label(
        canvas,
        '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(0)}',
        Offset(4, y - 14),
        size,
      );
    }

    // The curve. Cubic segments with control points on the midpoint keep it
    // smooth without overshooting past the nodes, which a spline through the
    // points would do — and an overshoot would draw a boost that is not set.
    final curve = Path()..moveTo(_x(0, size), _y(gains[0], size));
    for (var i = 1; i < gains.length; i++) {
      final x0 = _x(i - 1, size);
      final y0 = _y(gains[i - 1], size);
      final x1 = _x(i, size);
      final y1 = _y(gains[i], size);
      final mid = (x0 + x1) / 2;
      curve.cubicTo(mid, y0, mid, y1, x1, y1);
    }

    final area = Path.from(curve)
      ..lineTo(_x(gains.length - 1, size), _y(minGain, size))
      ..lineTo(_x(0, size), _y(minGain, size))
      ..close();
    canvas.drawPath(area, Paint()..color = fillColor.withValues(alpha: 0.14));

    canvas.drawPath(
      curve,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Nodes, and the frequency labels under alternating ones so a ten-band
    // graph stays readable at a narrow width.
    for (var i = 0; i < gains.length; i++) {
      final centre = Offset(_x(i, size), _y(gains[i], size));
      final active = i == activeBand;
      canvas.drawCircle(centre, active ? 7 : 5, Paint()..color = background);
      canvas.drawCircle(centre, active ? 5 : 3.2, Paint()..color = lineColor);
      if (active) {
        canvas.drawCircle(
          centre,
          9,
          Paint()
            ..color = lineColor.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
      if (i.isEven && i < frequencies.length) {
        _label(
          canvas,
          formatBandFrequency(frequencies[i]),
          Offset(centre.dx - 14, size.height - 14),
          size,
        );
      }
    }
  }

  /// Draws a small centred label, clamped so it never leaves the canvas.
  void _label(Canvas canvas, String text, Offset topLeft, Size size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final x = topLeft.dx.clamp(
      0.0,
      (size.width - painter.width).clamp(0.0, size.width),
    );
    painter.paint(canvas, Offset(x, topLeft.dy));
  }

  @override
  bool shouldRepaint(covariant EqGraphPainter old) =>
      old.activeBand != activeBand ||
      old.lineColor != lineColor ||
      old.background != background ||
      old.gains.join(',') != gains.join(',');
}
