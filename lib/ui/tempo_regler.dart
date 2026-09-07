import 'package:flutter/material.dart';

import '../theme/arcade_theme.dart';

/// Regler für die Abspielgeschwindigkeit in Handelstagen pro Sekunde.
class TempoRegler extends StatefulWidget {
  final double start;
  final ValueChanged<double> onChanged;

  const TempoRegler({super.key, required this.start, required this.onChanged});

  @override
  State<TempoRegler> createState() => _TempoReglerState();
}

class _TempoReglerState extends State<TempoRegler> {
  late double _wert = widget.start;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: _wert,
            min: 1,
            max: 100,
            onChanged: (v) {
              setState(() => _wert = v);
              widget.onChanged(v);
            },
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(
            '${_wert.round()}×',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: ArcadeFarben.tinteHell,
            ),
          ),
        ),
      ],
    );
  }
}
