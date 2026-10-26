// Hecz Support install wizard ("Paper").
//
// Replaces RustDesk 1.5.0's flutter/lib/desktop/pages/install_page.dart.
// apply_branding.py only swaps it in when the upstream file still has the
// SHA-256 it was written against, so a new RustDesk tag forces a review.
//
// States: welcome -> installing -> done | cancelled | failed.
// Progress comes from bind.installStatus() (src/ui_interface.rs), which
// reports real signals only: the Windows permission prompt was accepted, the
// files in the install folder match this build, and the elevated install
// script finished. There is no percentage because none would be honest.

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';

const _cream = Color(0xFFFAF8F5);
const _ink = Color(0xFF22172F);
const _muted = Color(0xFF5C5468);
const _plum = Color(0xFF2A1B3D);
const _plumDeep = Color(0xFF160F22);
const _mauve = Color(0xFF6B5D82);
const _mauveDark = Color(0xFF5A4D70);
const _lilac = Color(0xFF8B7DA8);
const _line = Color(0xFFE4DFD8);
const _note = Color(0xFFF3EEE6);
const _errorBg = Color(0xFFFBEDEB);
const _errorLine = Color(0xFFB4483C);
const _privacyUrl = 'https://hecz.dev/download#privacy';
const _licenseUrl = 'https://github.com/h3cz/hecz-support/blob/main/LICENSE';

class InstallPage extends StatefulWidget {
  const InstallPage({Key? key}) : super(key: key);

  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);

  _InstallPageState() {
    Get.put<DesktopTabController>(tabController);
    const label = "install";
    tabController.add(TabInfo(
        key: label,
        label: label,
        closable: false,
        page: _InstallPageBody(
          key: const ValueKey(label),
        )));
  }

  @override
  void dispose() {
    super.dispose();
    Get.delete<DesktopTabController>();
  }

  @override
  Widget build(BuildContext context) {
    // Paper is a light design whatever the Windows theme is.
    return Theme(
      data: MyTheme.lightTheme,
      child: DragToResizeArea(
        resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
        enableResizeEdges: windowManagerEnableResizeEdges,
        child: Scaffold(
            backgroundColor: _cream,
            body: DesktopTab(
              controller: tabController,
              showTitle: true,
              showMaximize: false,
            )),
      ),
    );
  }
}

enum _Stage { welcome, installing, done, cancelled, failed }

class _Status {
  final String state;
  final bool elevated;
  final bool copied;
  final String message;
  final bool reduceMotion;

  const _Status(this.state, this.elevated, this.copied, this.message,
      this.reduceMotion);

  static _Status read() {
    try {
      final m = jsonDecode(bind.installStatus()) as Map<String, dynamic>;
      return _Status(
        m['state'] as String? ?? 'idle',
        m['elevated'] == true,
        m['copied'] == true,
        m['message'] as String? ?? '',
        m['reduce_motion'] == true,
      );
    } catch (_) {
      return const _Status('idle', false, false, '', false);
    }
  }
}

class _InstallPageBody extends StatefulWidget {
  const _InstallPageBody({Key? key}) : super(key: key);

  @override
  State<_InstallPageBody> createState() => _InstallPageBodyState();
}

class _InstallPageBodyState extends State<_InstallPageBody>
    with WindowListener {
  late final TextEditingController pathController;
  bool startmenu = true;
  bool desktopicon = true;
  bool openNow = true;
  bool copied = false;
  _Stage stage = _Stage.welcome;
  _Status status = const _Status('idle', false, false, '', false);
  String id = '';
  Timer? _poll;
  Timer? _copiedReset;
  final _rootFocus = FocusNode(debugLabel: 'hecz-install');

  _InstallPageBodyState() {
    pathController = TextEditingController(text: bind.installInstallPath());
    final installOptions = jsonDecode(bind.installInstallOptions());
    startmenu = installOptions['STARTMENUSHORTCUTS'] != '0';
    desktopicon = installOptions['DESKTOPSHORTCUTS'] != '0';
    status = _Status.read();
  }

  bool get _reduceMotion =>
      status.reduceMotion || MediaQuery.of(this.context).disableAnimations;

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _copiedReset?.cancel();
    _rootFocus.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    gFFI.close();
    super.onWindowClose();
    windowManager.setPreventClose(false);
    windowManager.close();
  }

  void _install() {
    if (stage == _Stage.installing) return;
    String args = '';
    if (startmenu) args += ' startmenu';
    if (desktopicon) args += ' desktopicon';
    setState(() {
      stage = _Stage.installing;
      copied = false;
    });
    bind.installInstallMe(options: args, path: pathController.text);
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 300), (_) => _tick());
  }

  void _tick() {
    final s = _Status.read();
    var next = stage;
    switch (s.state) {
      case 'done':
        next = _Stage.done;
        break;
      case 'cancelled':
        next = _Stage.cancelled;
        break;
      case 'failed':
        next = _Stage.failed;
        break;
    }
    if (next != _Stage.installing) {
      _poll?.cancel();
      if (next == _Stage.done) _loadId();
    }
    if (!mounted) return;
    setState(() {
      status = s;
      stage = next;
    });
  }

  // The service imports this user's config, so its ID is the one shown here.
  // Re-read once the service has had a moment to answer over IPC.
  Future<void> _loadId() async {
    for (var i = 0; i < 4; i++) {
      final v = await bind.mainGetMyId();
      if (!mounted) return;
      if (v.isNotEmpty && v != id) setState(() => id = v);
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  void _selectInstallPath() async {
    String? installPath = await FilePicker.platform
        .getDirectoryPath(initialDirectory: pathController.text);
    if (installPath != null) {
      final p = join(installPath, await bind.mainGetAppName());
      setState(() => pathController.text = p);
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() => copied = true);
    _copiedReset?.cancel();
    _copiedReset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => copied = false);
    });
  }

  void _finish() {
    if (openNow) {
      bind.installOpenInstalled();
    } else {
      windowManager.close();
    }
  }

  void _escape() {
    switch (stage) {
      case _Stage.welcome:
      case _Stage.cancelled:
      case _Stage.failed:
        windowManager.close();
        break;
      case _Stage.done:
        setState(() => openNow = false);
        windowManager.close();
        break;
      case _Stage.installing:
        break; // the elevated script keeps running; don't hide it
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
      },
      // The primary button of each screen takes focus, so Enter activates it
      // and Esc bubbles up to here.
      child: Focus(
        focusNode: _rootFocus,
        canRequestFocus: false,
        skipTraversal: true,
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: _ink),
          child: Container(
            color: _cream,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _rail(),
                Expanded(
                  child: FocusTraversalGroup(
                    child: LayoutBuilder(
                      // Scroll instead of clipping when Windows text scaling
                      // makes a screen taller than the window; the Spacer in
                      // each screen still pins the buttons when it all fits.
                      builder: (context, box) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: box.maxHeight),
                          child: IntrinsicHeight(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(40, 32, 40, 24),
                              child: _body(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- left rail ---------------------------------------------------------

  Widget _rail() {
    final railStep = switch (stage) {
      _Stage.welcome => 0,
      _Stage.installing || _Stage.cancelled || _Stage.failed => 1,
      _Stage.done => 3,
    };
    Widget step(int i, String label) {
      final done = i < railStep;
      final now = i == railStep;
      return Semantics(
        label: '$label, step ${i + 1} of 3'
            '${done ? ', done' : now ? ', current' : ''}',
        excludeSemantics: true,
        child: Row(children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? _lilac
                  : now
                      ? const Color(0x2EB9ACD3)
                      : Colors.transparent,
              border: Border.all(
                  width: 1.5,
                  color: done
                      ? _lilac
                      : now
                          ? const Color(0xFFB9ACD3)
                          : const Color(0xFF6E6382)),
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 15, color: _plumDeep)
                : Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: now ? _cream : const Color(0xFFA99FBA))),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: now ? FontWeight.w600 : FontWeight.normal,
                  color: now
                      ? _cream
                      : done
                          ? const Color(0xFFD9D2E4)
                          : const Color(0xFFA99FBA))),
        ]),
      );
    }

    return Container(
      width: 210,
      padding: const EdgeInsets.fromLTRB(24, 28, 20, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_plum, _plumDeep],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x26FAF8F5)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/icon.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Hecz\nSupport',
              style: TextStyle(
                  color: _cream,
                  fontSize: 18,
                  height: 1.15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 30),
          step(0, 'Welcome'),
          const SizedBox(height: 16),
          step(1, 'Install'),
          const SizedBox(height: 16),
          step(2, 'Ready'),
          const Spacer(),
          const Text('hecz.dev',
              style: TextStyle(color: Color(0xFF8F86A0), fontSize: 12)),
        ],
      ),
    );
  }

  // ---- right side --------------------------------------------------------

  Widget _body() {
    switch (stage) {
      case _Stage.welcome:
        return _welcome();
      case _Stage.installing:
        return _installing();
      case _Stage.done:
        return _done();
      case _Stage.cancelled:
      case _Stage.failed:
        return _problem();
    }
  }

  Widget _title(String text) => Semantics(
        header: true,
        child: Text(text,
            style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: _plum,
                letterSpacing: -0.2)),
      );

  Widget _lede(List<InlineSpan> spans) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 18),
        child: Text.rich(TextSpan(children: spans),
            style: const TextStyle(fontSize: 15, height: 1.5, color: _muted)),
      );

  static const _bold = TextStyle(fontWeight: FontWeight.w700, color: _ink);

  Widget _welcome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Welcome'),
        _lede(const [
          TextSpan(
              text: 'Hecz Support lets Hecz see and help with your screen. '),
          TextSpan(
              text: 'By default, nothing happens until you say yes', style: _bold),
          TextSpan(
              text: ' to each connection. Installing keeps your ID the same '
                  'and makes it easier to reach next time.'),
        ]),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Semantics(
                    label: 'Install location, ${pathController.text}',
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _caps('Install location'),
                        const SizedBox(height: 4),
                        Text(pathController.text,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 13,
                                color: _ink)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: _ghostStyle,
                  onPressed: _selectInstallPath,
                  icon: const Icon(Icons.folder_outlined, size: 16),
                  label: const Text('Change…'),
                ),
              ]),
              const Divider(height: 22, color: _line),
              _check('Add to the Start menu', startmenu,
                  (v) => setState(() => startmenu = v)),
              _check('Put a shortcut on the desktop', desktopicon,
                  (v) => setState(() => desktopicon = v)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _noteBox(const [
          TextSpan(text: 'Heads-up: ', style: _bold),
          TextSpan(
              text: 'next, Windows asks “Do you want to allow this app to make '
                  'changes to your device?” and shows '),
          TextSpan(text: 'Unknown publisher', style: _bold),
          TextSpan(
              text: '. That is expected: this build is not code signed yet. '
                  'Click '),
          TextSpan(text: 'Yes', style: _bold),
          TextSpan(text: ' to continue.'),
        ]),
        const SizedBox(height: 10),
        _privacyLine(),
        const Spacer(),
        Row(children: [
          if (!bind.installShowRunWithoutInstall())
            Flexible(child: _runOnceLink()),
          const Spacer(),
          OutlinedButton(
            style: _ghostStyle,
            onPressed: () => windowManager.close(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            autofocus: true,
            style: _primaryStyle,
            onPressed: _install,
            child: const Text('Install'),
          ),
        ]),
      ],
    );
  }

  Widget _installing() {
    // Steps tick on real signals only (see the top of this file).
    final permission = status.elevated;
    final copying = permission && status.copied;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Installing'),
        _lede(const [
          TextSpan(text: 'Almost there. Please keep this window open.')
        ]),
        if (!_reduceMotion)
          Semantics(
            label: 'Installing',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: const LinearProgressIndicator(
                minHeight: 8,
                backgroundColor: Color(0xFFEBE5DC),
                color: _lilac,
              ),
            ),
          ),
        const SizedBox(height: 22),
        _step(
          'Windows permission',
          'Click Yes on the Windows prompt. It may say “Unknown publisher”.',
          permission ? _StepState.done : _StepState.now,
        ),
        _step(
          'Copying Hecz Support',
          'Into ${pathController.text}.',
          copying
              ? _StepState.done
              : permission
                  ? _StepState.now
                  : _StepState.waiting,
        ),
        _step(
          'Starting the background service',
          'So it can start with Windows and show the Accept window.',
          copying ? _StepState.now : _StepState.waiting,
        ),
      ],
    );
  }

  Widget _done() {
    final shown = id.isEmpty ? '…' : formatID(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('You’re ready'),
        _lede(const [TextSpan(text: 'Give this ID to Hecz when you need help.')]),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 16, 18, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
                colors: [_plum, Color(0xFF3B2A52)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
          child: Row(children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                label: id.isEmpty
                    ? 'Your Hecz Support ID is loading'
                    : 'Your Hecz Support ID: ${id.split('').join(' ')}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _caps('Your Hecz Support ID', color: const Color(0xFFCFC6DD)),
                    const SizedBox(height: 4),
                    SelectableText(shown,
                        style: const TextStyle(
                            color: _cream,
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            fontFeatures: [FontFeature.tabularFigures()])),
                  ],
                ),
              ),
            ),
            Semantics(
              button: true,
              label: copied ? 'ID copied' : 'Copy ID',
              excludeSemantics: true,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _cream,
                  foregroundColor: _plum,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                onPressed: id.isEmpty ? null : () => _copy(id),
                icon: Icon(copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 16),
                label: Text(copied ? 'Copied' : 'Copy ID'),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        Semantics(
          header: true,
          child: const Text('What happens next',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: _plum)),
        ),
        const SizedBox(height: 8),
        _bullet(const [
          TextSpan(text: 'Tell Hecz your ID', style: _bold),
          TextSpan(
              text: ' when you ask for help. The ID by itself doesn’t let '
                  'anyone in.'),
        ]),
        _bullet(const [
          TextSpan(text: 'You decide each time.', style: _bold),
          TextSpan(text: ' By default, a window asks you to '),
          TextSpan(text: 'Accept', style: _bold),
          TextSpan(text: ' or '),
          TextSpan(text: 'Cancel', style: _bold),
          TextSpan(
              text: ' every connection. Whoever owns this PC can change that '
                  'in Settings › Security.'),
        ]),
        _bullet(const [
          TextSpan(text: 'End it whenever you like.', style: _bold),
          TextSpan(text: ' The session window has a Disconnect button.'),
        ]),
        const Spacer(),
        Row(children: [
          _check('Open Hecz Support now', openNow,
              (v) => setState(() => openNow = v)),
          const Spacer(),
          ElevatedButton(
            autofocus: true,
            style: _primaryStyle,
            onPressed: _finish,
            child: const Text('Finish'),
          ),
        ]),
      ],
    );
  }

  Widget _problem() {
    final cancelled = stage == _Stage.cancelled;
    final details = status.message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(cancelled
            ? 'Windows permission wasn’t given'
            : 'The install didn’t finish'),
        _lede([
          TextSpan(
              text: cancelled
                  ? 'Installing needs a Yes on the Windows prompt. '
                      'Nothing was changed on this PC. '
                  : 'Something went wrong while installing. '),
          const TextSpan(text: 'Click '),
          const TextSpan(text: 'Try again', style: _bold),
          TextSpan(
              text: cancelled
                  ? ', then choose Yes when Windows asks. It may say '
                      '“Unknown publisher”, which is expected for this build.'
                  : '. If it happens again, send the details below to Hecz.'),
        ]),
        if (!cancelled)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _errorBg,
              borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8)),
              border: const Border(
                  left: BorderSide(color: _errorLine, width: 3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                      details.isEmpty ? 'No details were reported.' : details,
                      style: const TextStyle(
                          fontFamily: 'Consolas', fontSize: 12, color: _ink)),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: _mauve),
                  onPressed: () => _copy(details),
                  icon: Icon(copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 14),
                  label: Text(copied ? 'Copied' : 'Copy details'),
                ),
              ],
            ),
          ),
        const Spacer(),
        Row(children: [
          if (!bind.installShowRunWithoutInstall())
            Flexible(child: _runOnceLink()),
          const Spacer(),
          OutlinedButton(
            style: _ghostStyle,
            onPressed: () => windowManager.close(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            autofocus: true,
            style: _primaryStyle,
            onPressed: _install,
            child: const Text('Try again'),
          ),
        ]),
      ],
    );
  }

  // ---- pieces ------------------------------------------------------------

  Widget _caps(String text, {Color color = _muted}) => Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12, letterSpacing: 0.8, color: color),
      );

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) {
    return MergeSemantics(
      child: InkWell(
        // The checkbox itself is the tab stop (Space toggles it).
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(6),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: _mauve,
              side: const BorderSide(color: Color(0xFF9B92A8), width: 1.5),
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 14, color: _ink)),
          ]),
        ),
      ),
    );
  }

  Widget _noteBox(List<InlineSpan> spans) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(
          color: _note,
          borderRadius: BorderRadius.only(
              topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
          border: Border(left: BorderSide(color: _mauve, width: 3)),
        ),
        child: Text.rich(TextSpan(children: spans),
            style: const TextStyle(fontSize: 13, height: 1.5, color: _ink)),
      );

  Widget _privacyLine() => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Free software under the ',
              style: TextStyle(fontSize: 12, color: _muted)),
          _link('AGPL-3.0 license', () => launchUrlString(_licenseUrl),
              fontSize: 12),
          const Text('  ·  ', style: TextStyle(fontSize: 12, color: _muted)),
          _link('Privacy notice', () => launchUrlString(_privacyUrl),
              fontSize: 12),
        ],
      );

  Widget _runOnceLink() => _link('Run once without installing',
      () => bind.installRunWithoutInstall());

  Widget _link(String text, VoidCallback onTap, {double fontSize = 14}) {
    return Semantics(
      link: true,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: _mauve,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: TextStyle(
              fontSize: fontSize, decoration: TextDecoration.underline),
        ),
        onPressed: onTap,
        child: Text(text),
      ),
    );
  }

  Widget _bullet(List<InlineSpan> spans) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 7, left: 3, right: 10),
            width: 6,
            height: 6,
            decoration:
                const BoxDecoration(color: _mauve, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text.rich(TextSpan(children: spans),
                style: const TextStyle(
                    fontSize: 13.5, height: 1.45, color: _muted)),
          ),
        ]),
      );

  Widget _step(String title, String detail, _StepState s) {
    final Widget dot;
    switch (s) {
      case _StepState.done:
        dot = Container(
          width: 26,
          height: 26,
          decoration:
              const BoxDecoration(color: _mauve, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
        );
        break;
      case _StepState.now:
        dot = SizedBox(
          width: 26,
          height: 26,
          child: _reduceMotion
              ? Container(
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _mauve, width: 2.5)),
                  child: const Icon(Icons.more_horiz_rounded,
                      size: 14, color: _mauve),
                )
              : const CircularProgressIndicator(
                  strokeWidth: 2.5, color: _mauve),
        );
        break;
      case _StepState.waiting:
        dot = Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFCFC7BD), width: 2)),
        );
        break;
    }
    final stateWord = switch (s) {
      _StepState.done => 'done',
      _StepState.now => 'in progress',
      _StepState.waiting => 'waiting',
    };
    return Semantics(
      liveRegion: true,
      label: '$title, $stateWord. $detail',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          dot,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: s == _StepState.waiting
                            ? const Color(0xFF7D7488)
                            : _ink)),
                const SizedBox(height: 3),
                Text(detail,
                    style: const TextStyle(
                        fontSize: 13, height: 1.4, color: _muted)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  static final _primaryStyle = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
            ? _mauveDark
            : _mauve),
    foregroundColor: const WidgetStatePropertyAll(Colors.white),
    elevation: const WidgetStatePropertyAll(0),
    padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 26, vertical: 16)),
    textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    // A visible ring for keyboard users; the fill change alone is subtle.
    side: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.focused)
            ? const BorderSide(color: _plum, width: 2)
            : BorderSide.none),
  );

  static final _ghostStyle = ButtonStyle(
    foregroundColor: const WidgetStatePropertyAll(_ink),
    backgroundColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
            ? const Color(0xFFF1ECE4)
            : Colors.white),
    padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 15)),
    shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    side: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.focused)
            ? const BorderSide(color: _plum, width: 2)
            : const BorderSide(color: Color(0xFFCFC7BD))),
  );
}

enum _StepState { done, now, waiting }
