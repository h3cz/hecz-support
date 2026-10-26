// Hecz Support: one-time "you're installed" banner on the home screen.
// Shown on Windows once Hecz Support is installed, until the person closes it.
// The dismissal is a per-user local option, so it never comes back.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

const _kHeczFirstRunDone = 'hecz-first-run-done';

class HeczInstalledBanner extends StatefulWidget {
  const HeczInstalledBanner({Key? key}) : super(key: key);

  @override
  State<HeczInstalledBanner> createState() => _HeczInstalledBannerState();
}

class _HeczInstalledBannerState extends State<HeczInstalledBanner> {
  late bool _show = isWindows &&
      bind.mainIsInstalled() &&
      bind.mainGetLocalOption(key: _kHeczFirstRunDone) != 'Y';

  void _dismiss() {
    bind.mainSetLocalOption(key: _kHeczFirstRunDone, value: 'Y');
    setState(() => _show = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? const Color(0xFFF2EEF8) : const Color(0xFF22172F);
    const bold = TextStyle(fontWeight: FontWeight.w700);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2E2440) : const Color(0xFFEFE9F6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: dark ? const Color(0xFF4A3D60) : const Color(0xFFD6CCE4)),
        ),
        child: Row(children: [
          Icon(Icons.check_rounded,
              size: 18,
              color: dark ? const Color(0xFFB9ACD3) : const Color(0xFF6B5D82)),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              const TextSpan(children: [
                TextSpan(text: 'Hecz Support is installed.', style: bold),
                TextSpan(text: ' It starts with Windows. Look for the mauve '),
                TextSpan(text: 'h', style: bold),
                TextSpan(text: ' in the tray.'),
              ]),
              style: TextStyle(fontSize: 13, height: 1.4, color: fg),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: _dismiss,
            icon: Icon(Icons.close_rounded, size: 18, color: fg),
          ),
        ]),
      ),
    );
  }
}
