import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/exantas_companion_model.dart';
import 'package:flutter_hbb/models/exantas_session_report.dart';
import 'package:flutter_hbb/models/exantas_report_outbox.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/plugin/ui_manager.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;
  final _exantasCompanion = ExantasCompanionService();
  ExantasCompanionStatus? _exantasStatus;
  Timer? _exantasHeartbeatTimer;
  Timer? _exantasPendingSessionsTimer;
  bool _checkingPendingSessions = false;
  bool _pendingSessionsInitialized = false;
  bool _pendingSessionDialogOpen = false;
  bool _pendingSessionsListOpen = false;
  int _pendingSessionPollRetriesRemaining = 0;
  final Set<String> _knownPendingSessionIds = <String>{};
  final List<Map<String, dynamic>> _pendingSessionQueue =
      <Map<String, dynamic>>[];
  DesktopTabController? _mainTabController;
  Function(int, String)? _previousTabRemoved;
  late final void Function(int, String) _exantasTabRemovedHandler;

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    return _buildBlock(
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildLeftPane(context),
        if (!isIncomingOnly) const VerticalDivider(width: 1),
        if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
      ],
    ));
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget buildLeftPane(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    final children = <Widget>[
      if (!isOutgoingOnly) buildPresetPasswordWarning(),
      if (bind.isCustomClient())
        Align(
          alignment: Alignment.center,
          child: loadPowered(context),
        ),
      Align(
        alignment: Alignment.center,
        child: loadLogo(),
      ),
      buildTip(context),
      if (!isOutgoingOnly) buildIDBoard(context),
      if (!isOutgoingOnly) buildPasswordBoard(context),
      if (!isOutgoingOnly) buildExantasCompanionCard(context),
      FutureBuilder<Widget>(
        future: Future.value(
            Obx(() => buildHelpCards(stateGlobal.updateUrl.value))),
        builder: (_, data) {
          if (data.hasData) {
            if (isIncomingOnly) {
              if (isInHomePage()) {
                Future.delayed(Duration(milliseconds: 300), () {
                  _updateWindowSize();
                });
              }
            }
            return data.data!;
          } else {
            return const Offstage();
          }
        },
      ),
      buildPluginEntry(),
    ];
    if (isIncomingOnly) {
      children.addAll([
        Divider(),
        OnlineStatusWidget(
          onSvcStatusChanged: () {
            if (isInHomePage()) {
              Future.delayed(Duration(milliseconds: 300), () {
                _updateWindowSize();
              });
            }
          },
        ).marginOnly(bottom: 6, right: 6)
      ]);
    }
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: isIncomingOnly ? 280.0 : 200.0,
        color: Theme.of(context).colorScheme.background,
        child: Stack(
          children: [
            Column(
              children: [
                SingleChildScrollView(
                  controller: _leftPaneScrollController,
                  child: Column(
                    key: _childKey,
                    children: children,
                  ),
                ),
                Expanded(child: Container())
              ],
            ),
            if (isOutgoingOnly)
              Positioned(
                bottom: 6,
                left: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    child: Obx(
                      () => Icon(
                        Icons.settings,
                        color: _editHover.value
                            ? textColor
                            : Colors.grey.withOpacity(0.5),
                        size: 22,
                      ),
                    ),
                    onTap: () => {
                      if (DesktopSettingPage.tabKeys.isNotEmpty)
                        {
                          DesktopSettingPage.switch2page(
                              DesktopSettingPage.tabKeys[0])
                        }
                    },
                    onHover: (value) => _editHover.value = value,
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  buildRightPane(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ConnectionPage(),
    );
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11),
      height: 57,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            decoration: const BoxDecoration(color: MyTheme.accent),
          ).marginOnly(top: 5),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 25,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          translate("ID"),
                          style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.color
                                  ?.withOpacity(0.5)),
                        ).marginOnly(top: 5),
                        buildPopupMenu(context)
                      ],
                    ),
                  ),
                  Flexible(
                    child: GestureDetector(
                      onDoubleTap: () {
                        Clipboard.setData(
                            ClipboardData(text: model.serverId.text));
                        showToast(translate("Copied"));
                      },
                      child: TextFormField(
                        controller: model.serverId,
                        readOnly: true,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.only(top: 10, bottom: 10),
                        ),
                        style: TextStyle(
                          fontSize: 22,
                        ),
                      ).workaroundFreezeLinuxMint(),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      child: Tooltip(
        message: translate('Settings'),
        child: Obx(
          () => CircleAvatar(
            radius: 15,
            backgroundColor: hover.value
                ? Theme.of(context).scaffoldBackgroundColor
                : Theme.of(context).colorScheme.background,
            child: Icon(
              Icons.more_vert_outlined,
              size: 20,
              color: hover.value ? textColor : textColor?.withOpacity(0.5),
            ),
          ),
        ),
      ),
      onHover: (value) => hover.value = value,
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return buildPasswordBoard2(context, model);
          },
        ));
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    RxBool refreshHover = false.obs;
    RxBool editHover = false.obs;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Container(
      margin: EdgeInsets.only(left: 20.0, right: 16, top: 13, bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            height: 52,
            decoration: BoxDecoration(color: MyTheme.accent),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoSizeText(
                    translate("One-time Password"),
                    style: TextStyle(
                        fontSize: 14, color: textColor?.withOpacity(0.5)),
                    maxLines: 1,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onDoubleTap: () {
                            if (showOneTime) {
                              Clipboard.setData(
                                  ClipboardData(text: model.serverPasswd.text));
                              showToast(translate("Copied"));
                            }
                          },
                          child: TextFormField(
                            controller: model.serverPasswd,
                            readOnly: true,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.only(top: 14, bottom: 10),
                            ),
                            style: TextStyle(fontSize: 15),
                          ).workaroundFreezeLinuxMint(),
                        ),
                      ),
                      if (showOneTime)
                        AnimatedRotationWidget(
                          onPressed: () => bind.mainUpdateTemporaryPassword(),
                          child: Tooltip(
                            message: translate('Refresh Password'),
                            child: Obx(() => RotatedBox(
                                quarterTurns: 2,
                                child: Icon(
                                  Icons.refresh,
                                  color: refreshHover.value
                                      ? textColor
                                      : Color(0xFFDDDDDD),
                                  size: 22,
                                ))),
                          ),
                          onHover: (value) => refreshHover.value = value,
                        ).marginOnly(right: 8, top: 4),
                      if (!bind.isDisableSettings())
                        InkWell(
                          child: Tooltip(
                            message: translate('Change Password'),
                            child: Obx(
                              () => Icon(
                                Icons.edit,
                                color: editHover.value
                                    ? textColor
                                    : Color(0xFFDDDDDD),
                                size: 22,
                              ).marginOnly(right: 8, top: 4),
                            ),
                          ),
                          onTap: () => DesktopSettingPage.switch2page(
                              SettingsTabKey.safety),
                          onHover: (value) => editHover.value = value,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildExantasCompanionCard(BuildContext context) {
    final status = _exantasStatus;
    final enrolled = status?.enrolled == true;
    final technicianLoggedIn = status?.technicianLoggedIn == true;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final supportUserText = status == null
        ? ''
        : [
            if (status.technicianName.isNotEmpty) status.technicianName,
          ].join(' - ');
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 16, top: 0, bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Exantas Office',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            status?.modeLabel ?? 'Basic support mode',
            style: TextStyle(
                fontSize: 12, color: textColor?.withOpacity(0.7)),
          ),
          if (enrolled && (status?.customerName ?? '').isNotEmpty)
            Text(
              status!.customerName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, color: textColor?.withOpacity(0.6)),
            ),
          if (technicianLoggedIn)
            Text(
              supportUserText.isEmpty
                  ? 'Office user logged in'
                  : supportUserText,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, color: textColor?.withOpacity(0.6)),
            ),
          if (technicianLoggedIn && (status?.officeUserId ?? '').isEmpty)
            const Text('Κάνε νέα είσοδο στο Office για να ενεργοποιήσεις το τοπικό ιστορικό αναφορών.'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton(
                onPressed: () => _showEnrollDialog(context),
                child: Text(enrolled ? 'Re-enroll' : 'Enroll'),
              ),
              OutlinedButton(
                onPressed: () => _showTechnicianLoginDialog(context),
                child:
                    Text(technicianLoggedIn ? 'Switch user' : 'Office login'),
              ),
              if (technicianLoggedIn)
                OutlinedButton(
                  onPressed: () => DesktopSettingPage.switch2page(SettingsTabKey.supportSessions),
                  child: const Text('Αναφορές'),
                ),
              if (technicianLoggedIn)
                OutlinedButton(
                  onPressed: () => _runExantasAction(
                      () => _exantasCompanion.logoutTechnician()),
                  child: const Text('Logout'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _refreshExantasStatus() async {
    try {
      final next = await _exantasCompanion.loadStatus();
      if (!mounted) {
        return;
      }
      final pairingChanged =
          _exantasStatus?.companionToken != next.companionToken;
      setState(() {
        _exantasStatus = next;
      });
      if (pairingChanged) {
        _resetPendingSessionTracking();
        if (next.technicianLoggedIn) {
          unawaited(_pollExantasPendingSessions());
        }
      }
    } catch (e) {
      debugPrint('Exantas status refresh failed: $e');
    }
  }

  Future<void> _runExantasAction(Future<dynamic> Function() action) async {
    try {
      await action();
      await _refreshExantasStatus();
      showToast(translate('Successful'));
    } catch (e) {
      showToast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showEnrollDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enroll device'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Install code'),
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translate('Cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              final code = controller.text;
              Navigator.of(context).pop();
              _runExantasAction(() => _exantasCompanion.enrollDevice(code));
            },
            child: const Text('Enroll'),
          ),
        ],
      ),
    );
  }

  void _showTechnicianLoginDialog(BuildContext context) {
    final email = TextEditingController();
    final password = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Office login'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: 'Office email'),
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
              ),
              TextField(
                controller: password,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translate('Cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              final e = email.text;
              final p = password.text;
              Navigator.of(context).pop();
              _runExantasAction(() => _exantasCompanion.loginTechnician(e, p));
            },
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }

  void _resetPendingSessionTracking() {
    _checkingPendingSessions = false;
    _pendingSessionsInitialized = false;
    _knownPendingSessionIds.clear();
    _pendingSessionQueue.clear();
  }

  void _schedulePendingSessionPolls() {
    _pendingSessionPollRetriesRemaining = 4;
    _scheduleNextPendingSessionPoll();
  }

  void _scheduleNextPendingSessionPoll() {
    _exantasPendingSessionsTimer?.cancel();
    if (!mounted || _pendingSessionPollRetriesRemaining <= 0) {
      return;
    }
    _exantasPendingSessionsTimer = Timer(const Duration(seconds: 12), () async {
      final found = await _pollExantasPendingSessions();
      if (found) {
        _pendingSessionPollRetriesRemaining = 0;
        return;
      }
      _pendingSessionPollRetriesRemaining -= 1;
      _scheduleNextPendingSessionPoll();
    });
  }

  Future<bool> _pollExantasPendingSessions() async {
    if (_exantasStatus?.officeUserId.isNotEmpty == true) {
      await ExantasReportOutbox.instance.sync();
      return false;
    }
    if (!mounted ||
        _exantasStatus?.technicianLoggedIn != true ||
        _checkingPendingSessions ||
        _pendingSessionDialogOpen ||
        _pendingSessionsListOpen) {
      return false;
    }

    _checkingPendingSessions = true;
    var queuedNewSession = false;
    try {
      final sessions = await _exantasCompanion.pendingSessions();
      await ExantasReportOutbox.instance.sync();
      final localSessions = await ExantasReportOutbox.instance.rows();
      if (!mounted) {
        return false;
      }

      final validSessions = sessions
          .where((session) => _sessionId(session).isNotEmpty &&
              !localSessions.any((local) =>
                  local['peer_id'].toString() == session['peer_id'].toString() &&
                  local['rustdesk_session_id'].toString() == session['rustdesk_session_id'].toString()))
          .toList();
      if (!_pendingSessionsInitialized) {
        _pendingSessionsInitialized = true;
        _knownPendingSessionIds.addAll(validSessions.map(_sessionId));
        if (validSessions.isNotEmpty) {
          _pendingSessionQueue.add(validSessions.first);
          queuedNewSession = true;
        }
      } else {
        final newSessions = validSessions
            .where((session) =>
                !_knownPendingSessionIds.contains(_sessionId(session)))
            .toList()
            .reversed;
        for (final session in newSessions) {
          _knownPendingSessionIds.add(_sessionId(session));
          _pendingSessionQueue.add(session);
          queuedNewSession = true;
        }
      }
    } catch (e) {
      debugPrint('Office pending session refresh failed: $e');
    } finally {
      _checkingPendingSessions = false;
    }

    if (mounted && queuedNewSession) {
      unawaited(_showNextPendingSessionReport());
    }
    return queuedNewSession;
  }

  Future<void> _showNextPendingSessionReport() async {
    if (!mounted ||
        _pendingSessionDialogOpen ||
        _pendingSessionsListOpen ||
        _pendingSessionQueue.isEmpty) {
      return;
    }

    final session = _pendingSessionQueue.removeAt(0);
    final processed = await _presentSessionReport(session);
    if (!processed) {
      _pendingSessionQueue.clear();
      return;
    }
    if (mounted && _pendingSessionQueue.isNotEmpty) {
      unawaited(_showNextPendingSessionReport());
    }
  }

  Future<bool> _presentSessionReport(
      Map<String, dynamic> session) async {
    if (!mounted || _pendingSessionDialogOpen) {
      return false;
    }
    _pendingSessionDialogOpen = true;
    try {
      return await _showSessionReportDialog(context, session);
    } finally {
      _pendingSessionDialogOpen = false;
    }
  }

  void _showPendingSessionsDialog(BuildContext context) {
    unawaited(_openPendingSessionsDialog(context));
  }

  Future<void> _openPendingSessionsDialog(BuildContext ownerContext) async {
    if (_pendingSessionsListOpen || _pendingSessionDialogOpen) {
      return;
    }
    _pendingSessionsListOpen = true;
    Map<String, dynamic>? selectedSession;
    try {
      final sessions = await _exantasCompanion.pendingSessions();
      if (!mounted) {
        return;
      }
      _knownPendingSessionIds.addAll(sessions.map(_sessionId));
      selectedSession = await showDialog<Map<String, dynamic>>(
        context: ownerContext,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Εκκρεμείς αναφορές υποστήριξης'),
          content: SizedBox(
            width: 560,
            child: sessions.isEmpty
                ? const Text('Δεν υπάρχουν εκκρεμείς αναφορές.')
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 440),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: sessions.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (_, index) {
                        final session = sessions[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_sessionCustomer(session)),
                          subtitle: Text(
                            '${_sessionDevice(session)}\n'
                            '${_formatSessionDate(session['ended_at'])} · '
                            '${_formatSessionDuration(session)}',
                          ),
                          isThreeLine: true,
                          trailing: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(session),
                            child: const Text('Καταγραφή'),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Κλείσιμο'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        showToast(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      _pendingSessionsListOpen = false;
    }

    if (mounted && selectedSession != null) {
      await _presentSessionReport(selectedSession);
    }
  }

  Future<bool> _showSessionReportDialog(
    BuildContext ownerContext,
    Map<String, dynamic> session,
  ) async {
    final sessionId = _sessionId(session);
    if (sessionId.isEmpty) {
      showToast('Η συνεδρία δεν έχει έγκυρο αναγνωριστικό.');
      return false;
    }

    final noteController = TextEditingController();
    var outcome = ExantasSessionOutcome.completed;
    var submitting = false;
    String? errorMessage;
    final idempotencyKey =
        'companion-$sessionId-${DateTime.now().microsecondsSinceEpoch}';

    final processed = await showDialog<bool>(
          context: ownerContext,
          barrierDismissible: false,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              Future<void> submit() async {
                final note = noteController.text.trim();
                if (outcome != ExantasSessionOutcome.noRecord &&
                    note.isEmpty) {
                  setDialogState(() {
                    errorMessage = 'Το σχόλιο υποστήριξης είναι υποχρεωτικό.';
                  });
                  return;
                }

                if (outcome == ExantasSessionOutcome.completed) {
                  final confirmed = await showDialog<bool>(
                        context: dialogContext,
                        barrierDismissible: false,
                        builder: (confirmationContext) => AlertDialog(
                          title: const Text('Ολοκλήρωση και αποστολή αναφοράς'),
                          content: Text(
                            'Μετά τον συγχρονισμό θα κλείσει η ανοικτή υπόθεση του πελάτη '
                            'που αντιστοιχεί στον υπολογιστή ${session['peer_id']} και θα σταλεί η '
                            'αναφορά στο αποθηκευμένο email του. Θέλεις να '
                            'συνεχίσεις;',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(confirmationContext).pop(false),
                              child: const Text('Ακύρωση'),
                            ),
                            ElevatedButton(
                              onPressed: () =>
                                  Navigator.of(confirmationContext).pop(true),
                              child: const Text('Επιβεβαίωση και αποστολή'),
                            ),
                          ],
                        ),
                      ) ??
                      false;
                  if (!confirmed) {
                    return;
                  }
                }

                setDialogState(() {
                  submitting = true;
                  errorMessage = null;
                });
                try {
                  if (session['local_report'] == true) {
                    await ExantasReportOutbox.instance.save(sessionId, outcome, note);
                    unawaited(ExantasReportOutbox.instance.sync());
                  } else {
                    await _exantasCompanion.submitSessionReport(
                    sessionId,
                    outcome,
                    note,
                    idempotencyKey: idempotencyKey,
                  );
                  }
                  if (!mounted) {
                    return;
                  }
                  Navigator.of(dialogContext).pop(true);
                  showToast(session['local_report'] == true
                      ? 'Η αναφορά αποθηκεύτηκε στον υπολογιστή. Αναμονή συγχρονισμού.'
                      : _sessionReportSuccessMessage(outcome));
                } catch (e) {
                  if (!mounted) {
                    return;
                  }
                  setDialogState(() {
                    submitting = false;
                    errorMessage =
                        e.toString().replaceFirst('Exception: ', '');
                  });
                }
              }

              return AlertDialog(
                title: const Text('Καταγραφή υποστήριξης'),
                content: SizedBox(
                  width: 560,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Η απομακρυσμένη σύνδεση ολοκληρώθηκε. Κατάγραψε '
                          'το αποτέλεσμα χωρίς να ανοίξεις το Office.',
                        ),
                        const SizedBox(height: 16),
                        _buildSessionReportDetail(
                            'Πελάτης', _sessionCustomer(session)),
                        _buildSessionReportDetail(
                            'Υπολογιστής', _sessionDevice(session)),
                        _buildSessionReportDetail(
                            'RustDesk ID', _stringValue(session['peer_id'])),
                        _buildSessionReportDetail(
                          'Συνεδρία',
                          '${_formatSessionDate(session['ended_at'])} · '
                              '${_formatSessionDuration(session)}',
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<ExantasSessionOutcome>(
                          value: outcome,
                          decoration:
                              const InputDecoration(labelText: 'Αποτέλεσμα'),
                          items: ExantasSessionOutcome.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_sessionOutcomeLabel(value)),
                                ),
                              )
                              .toList(),
                          onChanged: submitting
                              ? null
                              : (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setDialogState(() {
                                    outcome = value;
                                    errorMessage = null;
                                  });
                                },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: noteController,
                          enabled: !submitting &&
                              outcome != ExantasSessionOutcome.noRecord,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 2000,
                          decoration: InputDecoration(
                            labelText: 'Σχόλιο υποστήριξης',
                            hintText: outcome ==
                                    ExantasSessionOutcome.noRecord
                                ? 'Δεν απαιτείται σχόλιο.'
                                : 'Γράψε τι πραγματοποιήθηκε.',
                          ),
                        ),
                        Text(
                          _sessionOutcomeHelp(outcome),
                          style: Theme.of(dialogContext).textTheme.bodySmall,
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            errorMessage!,
                            style: TextStyle(
                              color: Theme.of(dialogContext).colorScheme.error,
                            ),
                          ),
                        ],
                        if (submitting) ...[
                          const SizedBox(height: 12),
                          const LinearProgressIndicator(),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Αργότερα'),
                  ),
                  ElevatedButton(
                    onPressed: submitting ? null : submit,
                    child: Text(session['local_report'] == true
                        ? 'Αποθήκευση αναφοράς'
                        : _sessionSubmitLabel(outcome)),
                  ),
                ],
              );
            },
          ),
        ) ??
        false;
    noteController.dispose();
    return processed;
  }

  Widget _buildSessionReportDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }

  String _sessionId(Map<String, dynamic> session) =>
      _stringValue(session['id']);

  String _sessionCustomer(Map<String, dynamic> session) {
    final value = _stringValue(session['customer_name']);
    return value.isEmpty ? 'Άγνωστος πελάτης' : value;
  }

  String _sessionDevice(Map<String, dynamic> session) {
    for (final value in [
      session['customer_device_label'],
      session['peer_name'],
      session['peer_id'],
    ]) {
      final text = _stringValue(value);
      if (text.isNotEmpty) {
        return text;
      }
    }
    return 'Άγνωστος υπολογιστής';
  }

  String _formatSessionDate(dynamic value) {
    final date = DateTime.tryParse(_stringValue(value));
    if (date == null) {
      return 'Άγνωστη ημερομηνία';
    }
    final local = date.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  String _formatSessionDuration(Map<String, dynamic> session) {
    final seconds = int.tryParse('${session['duration_seconds'] ?? 0}') ?? 0;
    final minutes = (seconds / 60).ceil();
    return '$minutes ${minutes == 1 ? 'λεπτό' : 'λεπτά'}';
  }

  String _stringValue(dynamic value) => '${value ?? ''}'.trim();

  String _sessionOutcomeLabel(ExantasSessionOutcome outcome) {
    switch (outcome) {
      case ExantasSessionOutcome.completed:
        return 'Ολοκληρώθηκε';
      case ExantasSessionOutcome.followUp:
        return 'Χρειάζεται συνέχεια';
      case ExantasSessionOutcome.noRecord:
        return 'Χωρίς καταγραφή';
    }
  }

  String _sessionOutcomeHelp(ExantasSessionOutcome outcome) {
    switch (outcome) {
      case ExantasSessionOutcome.completed:
        return 'Κλείνει την ανοικτή υπόθεση και στέλνει την αναφορά μετά '
            'από επιβεβαίωση.';
      case ExantasSessionOutcome.followUp:
        return 'Προσθέτει εργασία στην ανοικτή υπόθεση χωρίς αποστολή email.';
      case ExantasSessionOutcome.noRecord:
        return 'Σημειώνει τη συνεδρία ως μη καταχωρισμένη και την αφαιρεί '
            'από τις εκκρεμότητες.';
    }
  }

  String _sessionSubmitLabel(ExantasSessionOutcome outcome) {
    switch (outcome) {
      case ExantasSessionOutcome.completed:
        return 'Ολοκλήρωση και αποστολή';
      case ExantasSessionOutcome.followUp:
        return 'Αποθήκευση για συνέχεια';
      case ExantasSessionOutcome.noRecord:
        return 'Χωρίς καταγραφή';
    }
  }

  String _sessionReportSuccessMessage(ExantasSessionOutcome outcome) {
    switch (outcome) {
      case ExantasSessionOutcome.completed:
        return 'Η αναφορά καταχωρίστηκε και η αποστολή email ξεκίνησε.';
      case ExantasSessionOutcome.followUp:
        return 'Η εργασία προστέθηκε στην ανοικτή υπόθεση.';
      case ExantasSessionOutcome.noRecord:
        return 'Η συνεδρία αφαιρέθηκε από τις εκκρεμείς αναφορές.';
    }
  }

  buildTip(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Padding(
      padding:
          const EdgeInsets.only(left: 20.0, right: 16, top: 16.0, bottom: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              if (!isOutgoingOnly)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    translate("Your Desktop"),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 10.0,
          ),
          if (!isOutgoingOnly)
            Text(
              translate("desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (isOutgoingOnly)
            Text(
              translate("outgoing_only_desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('rustdesk')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://exantas.eu');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true,
          help: isToUpdate ? 'Changelog' : null,
          link: isToUpdate ? 'https://exantas.eu' : null);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://exantas.eu',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://exantas.eu'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://exantas.eu'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
              0, marginTop, 0, bind.isIncomingOnly() ? marginTop : 0),
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              )),
              padding: EdgeInsets.all(20),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (title.isNotEmpty
                          ? <Widget>[
                              Center(
                                  child: Text(
                                translate(title),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ).marginOnly(bottom: 6)),
                            ]
                          : <Widget>[]) +
                      <Widget>[
                        if (content.isNotEmpty)
                          Text(
                            translate(content),
                            style: TextStyle(
                                height: 1.5,
                                color: Colors.white,
                                fontWeight: FontWeight.normal,
                                fontSize: 13),
                          ).marginOnly(bottom: 20)
                      ] +
                      (btnText.isNotEmpty
                          ? <Widget>[
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FixedWidthButton(
                                      width: 150,
                                      padding: 8,
                                      isOutline: true,
                                      text: translate(btnText),
                                      textColor: Colors.white,
                                      borderColor: Colors.white,
                                      textSize: 20,
                                      radius: 10,
                                      onTap: onPressed,
                                    )
                                  ])
                            ]
                          : <Widget>[]) +
                      (help != null
                          ? <Widget>[
                              Center(
                                  child: InkWell(
                                      onTap: () async =>
                                          await launchUrl(Uri.parse(link!)),
                                      child: Text(
                                        translate(help),
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            color: Colors.white,
                                            fontSize: 12),
                                      )).marginOnly(top: 6)),
                            ]
                          : <Widget>[]))),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // rustDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    _refreshExantasStatus();
    ExantasReportOutbox.instance.openReport = (row) async {
      await _presentSessionReport(row);
    };
    _exantasHeartbeatTimer =
        periodic_immediate(const Duration(seconds: 60), () async {
      await ExantasReportOutbox.instance.sync();
      await _exantasCompanion.heartbeat();
      await _refreshExantasStatus();
      await _pollExantasPendingSessions();
    });
    _exantasTabRemovedHandler = (index, key) {
      _previousTabRemoved?.call(index, key);
      if (key != kTabLabelSettingPage) {
        _schedulePendingSessionPolls();
      }
    };
    try {
      _mainTabController = Get.find<DesktopTabController>();
      _previousTabRemoved = _mainTabController?.onRemoved;
      _mainTabController?.onRemoved = _exantasTabRemovedHandler;
    } catch (e) {
      debugPrint('Office session close listener setup failed: $e');
    }
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse:
          return true;
      }

      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      // Process local lifecycle messages before the generic diagnostic logger.
      if (call.method == 'officeSessionStarted') {
        await ExantasReportOutbox.instance.started(
            Map<String, dynamic>.from(call.arguments as Map));
        return true;
      }
      if (call.method == 'officeSessionEnded') {
        final row = await ExantasReportOutbox.instance.ended(
            Map<String, dynamic>.from(call.arguments as Map));
        final ownedRows = await ExantasReportOutbox.instance.rows();
        if (row != null && mounted && ownedRows.any((item) => item['id'] == row['id'])) {
          _pendingSessionQueue.add(row);
          windowOnTop(null);
          unawaited(_showNextPendingSessionReport());
          _schedulePendingSessionPolls();
        }
        return true;
      }
      if (!isChattyMethod(call.method)) {
        debugPrint(
            "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance
            .bumpMouse(dx: call.arguments['dx'], dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    _exantasHeartbeatTimer?.cancel();
    ExantasReportOutbox.instance.openReport = null;
    _exantasPendingSessionsTimer?.cancel();
    if (identical(
        _mainTabController?.onRemoved, _exantasTabRemovedHandler)) {
      _mainTabController?.onRemoved = _previousTabRemoved;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          })
        ],
      ),
    );
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final p0 = TextEditingController(text: "");
  final p1 = TextEditingController(text: "");
  var errMsg0 = "";
  var errMsg1 = "";
  final localPasswordSet =
      (await bind.mainGetCommon(key: "local-permanent-password-set")) == "true";
  final permanentPasswordSet =
      (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
  final presetPassword = permanentPasswordSet && !localPasswordSet;
  var canSubmit = false;
  final RxString rxPass = "".obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();
  final statusTip = localPasswordSet
      ? translate('password-hidden-tip')
      : (presetPassword ? translate('preset-password-in-use-tip') : '');
  final showStatusTipOnMobile =
      statusTip.isNotEmpty && !isDesktop && !isWebDesktop;

  gFFI.dialogManager.show((setState, close, context) {
    updateCanSubmit() {
      canSubmit = p0.text.trim().isNotEmpty || p1.text.trim().isNotEmpty;
    }

    submit() async {
      if (!canSubmit) {
        return;
      }
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pass);
      if (!ok) {
        setState(() {
          errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
        });
        return;
      }
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.key, color: MyTheme.accent),
          Text(translate("Set Password")).paddingOnly(left: 10),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 6.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginOnly(top: 2, bottom: showStatusTipOnMobile ? 2 : 8),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            if (statusTip.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.info, color: Colors.amber, size: 18)
                      .marginOnly(right: 6),
                  Expanded(
                      child: Text(
                    statusTip,
                    style: const TextStyle(fontSize: 13, height: 1.1),
                  ))
                ],
              ).marginOnly(top: 6, bottom: 2),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: showStatusTipOnMobile ? 2.0 : 8.0,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: (() {
        final cancelButton = dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        );
        final removeButton = dialogButton(
          "Remove",
          icon: Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            setState(() {
              errMsg0 = "";
              errMsg1 = "";
            });
            final ok =
                await bind.mainSetPermanentPasswordWithResult(password: "");
            if (!ok) {
              setState(() {
                errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
              });
              return;
            }
            close();
          },
          buttonStyle: ButtonStyle(
              backgroundColor: MaterialStatePropertyAll(Colors.red)),
        );
        final okButton = dialogButton(
          "OK",
          icon: Icon(Icons.done_rounded),
          onPressed: canSubmit ? submit : null,
        );
        if (!isDesktop && !isWebDesktop && localPasswordSet) {
          return [
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cancelButton,
                    const SizedBox(width: 4),
                    removeButton,
                    const SizedBox(width: 4),
                    okButton,
                  ],
                ),
              ),
            ),
          ];
        }
        return [
          cancelButton,
          if (localPasswordSet) removeButton,
          okButton,
        ];
      })(),
      onSubmit: canSubmit ? submit : null,
      onCancel: close,
    );
  });
}
