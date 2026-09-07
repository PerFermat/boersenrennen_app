import 'package:flutter/material.dart';

import '../theme/arcade_theme.dart';

/// Runder, „bonbonartiger" Knopf mit hartem Schlagschatten, der beim
/// Drücken einsinkt.
class CandyButton extends StatefulWidget {
  final String text;
  final Color farbe;
  final Color schatten;
  final VoidCallback? onTap;
  final IconData? icon;

  const CandyButton({
    super.key,
    required this.text,
    required this.farbe,
    required this.schatten,
    this.onTap,
    this.icon,
  });

  @override
  State<CandyButton> createState() => _CandyButtonState();
}

class _CandyButtonState extends State<CandyButton> {
  bool _gedrueckt = false;

  @override
  Widget build(BuildContext context) {
    final aktiv = widget.onTap != null;
    final versatz = _gedrueckt ? 3.0 : 0.0;

    return GestureDetector(
      onTapDown: aktiv ? (_) => setState(() => _gedrueckt = true) : null,
      onTapUp: aktiv ? (_) => setState(() => _gedrueckt = false) : null,
      onTapCancel: aktiv ? () => setState(() => _gedrueckt = false) : null,
      onTap: widget.onTap,
      child: Opacity(
        opacity: aktiv ? 1 : 0.45,
        child: Padding(
          padding: EdgeInsets.only(top: versatz, bottom: 3 - versatz),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: widget.farbe,
              borderRadius: BorderRadius.circular(14),
              boxShadow: _gedrueckt
                  ? null
                  : [BoxShadow(color: widget.schatten, offset: const Offset(0, 3), blurRadius: 0)],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                ],
                Text(
                  widget.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Eine der drei Depot-Wertkarten unter der Rennbahn.
class DepotKarte extends StatelessWidget {
  final String titel;
  final String wert;
  final Color farbe;
  final Color textFarbe;
  final bool hervorheben;

  const DepotKarte({
    super.key,
    required this.titel,
    required this.wert,
    required this.farbe,
    required this.textFarbe,
    this.hervorheben = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: farbe, width: hervorheben ? 3 : 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            titel,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: ArcadeFarben.tinteHell,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              wert,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: textFarbe,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
