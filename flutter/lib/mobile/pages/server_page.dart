import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import '../ui/ex_card.dart';
import '../ui/ex_empty_state.dart';
import '../ui/ex_list_row.dart';
import '../ui/ex_section_header.dart';
import '../ui/ex_status_pill.dart';
import '../ui/exantas_strings.dart';
import '../ui/exantas_theme.dart';
import 'home_page.dart';

class ServerPage extends StatefulWidget implements PageShape {
  @override
  final title = translate("Share screen");

  @override
  final icon = const Icon(Icons.mobile_screen_share);

  @override
  final appBarActions = (!bind.isDisableSettings() &&
          bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) != 'Y')
      ? [_DropDownAction()]
      : [];

  ServerPage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ServerPageState();
}

class _DropDownAction extends StatelessWidget {
  _DropDownAction();

  // should only have one action
  final actions = [
    PopupMenuButton<String>(
        tooltip: "",
        icon: const Icon(Icons.more_vert),
        itemBuilder: (context) {
          listTile(String text, bool checked) {
            return ListTile(
                title: Text(translate(text)),
                trailing: Icon(
                  Icons.check,
                  color: checked ? null : Colors.transparent,
                ));
          }

          final approveMode = gFFI.serverModel.approveMode;
          final verificationMethod = gFFI.serverModel.verificationMethod;
          final showPasswordOption = approveMode != 'click';
          final isApproveModeFixed = isOptionFixed(kOptionApproveMode);
          final isNumericOneTimePasswordFixed =
              isOptionFixed(kOptionAllowNumericOneTimePassword);
          final isAllowNumericOneTimePassword =
              gFFI.serverModel.allowNumericOneTimePassword;
          return [
            if (!isChangeIdDisabled())
              PopupMenuItem(
                enabled: gFFI.serverModel.connectStatus > 0,
                value: "changeID",
                child: Text(translate("Change ID")),
              ),
            if (!isChangeIdDisabled()) const PopupMenuDivider(),
            PopupMenuItem(
              value: 'AcceptSessionsViaPassword',
              child: listTile(
                  'Accept sessions via password', approveMode == 'password'),
              enabled: !isApproveModeFixed,
            ),
            PopupMenuItem(
              value: 'AcceptSessionsViaClick',
              child:
                  listTile('Accept sessions via click', approveMode == 'click'),
              enabled: !isApproveModeFixed,
            ),
            PopupMenuItem(
              value: "AcceptSessionsViaBoth",
              child: listTile("Accept sessions via both",
                  approveMode != 'password' && approveMode != 'click'),
              enabled: !isApproveModeFixed,
            ),
            if (showPasswordOption) const PopupMenuDivider(),
            if (showPasswordOption &&
                verificationMethod != kUseTemporaryPassword &&
                !isChangePermanentPasswordDisabled())
              PopupMenuItem(
                value: "setPermanentPassword",
                child: Text(translate("Set permanent password")),
              ),
            if (showPasswordOption &&
                verificationMethod != kUsePermanentPassword)
              PopupMenuItem(
                value: "setTemporaryPasswordLength",
                child: Text(translate("One-time password length")),
              ),
            if (showPasswordOption &&
                verificationMethod != kUsePermanentPassword)
              PopupMenuItem(
                value: "allowNumericOneTimePassword",
                child: listTile(translate("Numeric one-time password"),
                    isAllowNumericOneTimePassword),
                enabled: !isNumericOneTimePasswordFixed,
              ),
            if (showPasswordOption) const PopupMenuDivider(),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUseTemporaryPassword,
                child: listTile('Use one-time password',
                    verificationMethod == kUseTemporaryPassword),
              ),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUsePermanentPassword,
                child: listTile('Use permanent password',
                    verificationMethod == kUsePermanentPassword),
              ),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUseBothPasswords,
                child: listTile(
                    'Use both passwords',
                    verificationMethod != kUseTemporaryPassword &&
                        verificationMethod != kUsePermanentPassword),
              ),
          ];
        },
        onSelected: (value) async {
          if (value == "changeID") {
            changeIdDialog();
          } else if (value == "setPermanentPassword") {
            setPasswordDialog();
          } else if (value == "setTemporaryPasswordLength") {
            setTemporaryPasswordLengthDialog(gFFI.dialogManager);
          } else if (value == "allowNumericOneTimePassword") {
            gFFI.serverModel.switchAllowNumericOneTimePassword();
            gFFI.serverModel.updatePasswordModel();
          } else if (value == kUsePermanentPassword ||
              value == kUseTemporaryPassword ||
              value == kUseBothPasswords) {
            callback() {
              bind.mainSetOption(key: kOptionVerificationMethod, value: value);
              gFFI.serverModel.updatePasswordModel();
            }

            if (value == kUsePermanentPassword &&
                (await bind.mainGetCommon(key: "permanent-password-set")) !=
                    "true") {
              if (isChangePermanentPasswordDisabled()) {
                callback();
                return;
              }
              setPasswordDialog(notEmptyCallback: callback);
            } else {
              callback();
            }
          } else if (value.startsWith("AcceptSessionsVia")) {
            value = value.substring("AcceptSessionsVia".length);
            if (value == "Password") {
              gFFI.serverModel.setApproveMode('password');
            } else if (value == "Click") {
              gFFI.serverModel.setApproveMode('click');
            } else {
              gFFI.serverModel.setApproveMode(defaultOptionApproveMode);
            }
          }
        })
  ];

  @override
  Widget build(BuildContext context) {
    return actions[0];
  }
}

class _ServerPageState extends State<ServerPage> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 3), () async {
      await gFFI.serverModel.fetchID();
    });
    gFFI.serverModel.checkAndroidPermission();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    checkService();
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
            builder: (context, serverModel, child) => ColoredBox(
                color: context.ex.surfaceAlt,
                child: SingleChildScrollView(
                  controller: gFFI.serverModel.controller,
                  padding: const EdgeInsets.fromLTRB(
                      ExantasTokens.gutter,
                      ExantasTokens.space4,
                      ExantasTokens.gutter,
                      ExantasTokens.space8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      buildPresetPasswordWarningMobile(),
                      gFFI.serverModel.isStart
                          ? ServerInfo()
                          : ServiceNotRunningNotification(),
                      const ConnectionManager(),
                      const PermissionChecker(),
                    ],
                  ),
                ))));
  }
}

void checkService() async {
  gFFI.invokeMethod("check_service");
  // for Android 10/11, request MANAGE_EXTERNAL_STORAGE permission from system setting page
  if (AndroidPermissionManager.isWaitingFile() && !gFFI.serverModel.fileOk) {
    AndroidPermissionManager.complete(kManageExternalStorage,
        await AndroidPermissionManager.check(kManageExternalStorage));
    debugPrint("file permission finished");
  }
}

class ServiceNotRunningNotification extends StatelessWidget {
  ServiceNotRunningNotification({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);

    return PaddingCard(
        title: translate("Service is not running"),
        titleIcon: Icon(Icons.warning_amber_rounded, color: context.ex.warning),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(translate("android_start_service_tip"),
                    style: Theme.of(context).textTheme.bodySmall)
                .marginOnly(bottom: ExantasTokens.space3),
            FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                onPressed: () {
                  if (gFFI.userModel.userName.value.isEmpty &&
                      bind.mainGetLocalOption(key: "show-scam-warning") !=
                          "N") {
                    showScamWarning(context, serverModel);
                  } else {
                    serverModel.toggleService();
                  }
                },
                label: Text(translate("Start service")))
          ],
        ));
  }
}

class ScamWarningDialog extends StatefulWidget {
  final ServerModel serverModel;

  ScamWarningDialog({required this.serverModel});

  @override
  ScamWarningDialogState createState() => ScamWarningDialogState();
}

class ScamWarningDialogState extends State<ScamWarningDialog> {
  int _countdown = bind.isCustomClient() ? 0 : 12;
  bool show_warning = false;
  late Timer _timer;
  late ServerModel _serverModel;

  @override
  void initState() {
    super.initState();
    _serverModel = widget.serverModel;
    startCountdown();
  }

  void startCountdown() {
    const oneSecond = Duration(seconds: 1);
    _timer = Timer.periodic(oneSecond, (timer) {
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isButtonLocked = _countdown > 0;
    final t = context.ex;
    final text = Theme.of(context).textTheme;

    return AlertDialog(
      scrollable: true,
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: t.danger),
          const SizedBox(width: ExantasTokens.space2),
          Expanded(child: Text(translate("Warning"))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Image.asset(
              'assets/scam.png',
              width: 160,
            ),
          ),
          const SizedBox(height: ExantasTokens.space3),
          Text(
            translate("scam_title"),
            textAlign: TextAlign.center,
            style: text.titleMedium,
          ),
          const SizedBox(height: ExantasTokens.space3),
          Text(
            "${translate("scam_text1")}\n\n${translate("scam_text2")}",
            style: text.bodyMedium,
          ),
          const SizedBox(height: ExantasTokens.space2),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: show_warning,
            onChanged: (value) {
              setState(() {
                show_warning = value!;
              });
            },
            title: Text(translate("Don't show again")),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(
            translate("Decline"),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        FilledButton(
          onPressed: isButtonLocked
              ? null
              : () {
                  Navigator.of(context).pop();
                  _serverModel.toggleService();
                  if (show_warning) {
                    bind.mainSetLocalOption(
                        key: "show-scam-warning", value: "N");
                  }
                },
          child: Text(
            isButtonLocked
                ? "${translate("I Agree")} (${_countdown}s)"
                : translate("I Agree"),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class ServerInfo extends StatefulWidget {
  ServerInfo({Key? key}) : super(key: key);

  @override
  State<ServerInfo> createState() => _ServerInfoState();
}

class _ServerInfoState extends State<ServerInfo> {
  final model = gFFI.serverModel;
  bool _showPassword = false;

  void _copyToClipboard(String value) {
    Clipboard.setData(ClipboardData(text: value));
    showToast(translate('Copied'));
  }

  Widget _connectionStatus(ServerModel serverModel) {
    if (serverModel.connectStatus == -1) {
      return ExStatusPill(translate('not_ready_status'),
          status: ExStatus.danger, icon: Icons.warning_amber_rounded);
    } else if (serverModel.connectStatus == 0) {
      return ExStatusPill(translate('connecting_status'),
          status: ExStatus.warning, icon: Icons.sync);
    } else {
      return ExStatusPill(translate('Ready'), status: ExStatus.success);
    }
  }

  Widget _field(BuildContext context,
      {required String label,
      required IconData icon,
      required String value,
      required List<Widget> actions}) {
    final t = context.ex;
    final text = Theme.of(context).textTheme;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: ExantasTokens.space1),
        child: Row(children: [
          Icon(icon, size: 22, color: t.textSecondary),
          const SizedBox(width: ExantasTokens.space3),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label, style: text.labelMedium),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleLarge?.copyWith(
                        fontSize: 22,
                        letterSpacing: 1,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ])),
          ...actions,
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    final t = context.ex;

    final showOneTime = serverModel.approveMode != 'click' &&
        serverModel.verificationMethod != kUsePermanentPassword;
    final password = model.serverPasswd.value.text;
    return Padding(
        padding: const EdgeInsets.only(bottom: ExantasTokens.space4),
        child: ExCard(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                  child: Semantics(
                      header: true,
                      child: Text(translate('Your Device'),
                          style: Theme.of(context).textTheme.titleMedium))),
              _connectionStatus(serverModel),
            ]),
            const SizedBox(height: ExantasTokens.space3),
            _field(context,
                label: translate('ID'),
                icon: Icons.perm_identity,
                value: model.serverId.value.text,
                actions: [
                  IconButton(
                      tooltip: ExStrings.copyId,
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: () {
                        _copyToClipboard(model.serverId.value.text.trim());
                      })
                ]),
            Divider(height: ExantasTokens.space4, color: t.border),
            _field(context,
                label: translate('One-time Password'),
                icon: Icons.lock_outline,
                value:
                    !showOneTime ? '-' : (_showPassword ? password : '•' * 6),
                actions: !showOneTime
                    ? const []
                    : [
                        IconButton(
                            tooltip: _showPassword
                                ? ExStrings.hidePassword
                                : ExStrings.showPassword,
                            icon: Icon(_showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword)),
                        IconButton(
                            tooltip: ExStrings.newPassword,
                            icon: const Icon(Icons.refresh),
                            onPressed: () =>
                                bind.mainUpdateTemporaryPassword()),
                        IconButton(
                            tooltip: ExStrings.copyPassword,
                            icon: const Icon(Icons.copy_outlined),
                            onPressed: () {
                              _copyToClipboard(password.trim());
                            })
                      ]),
          ],
        )));
  }
}

class PermissionChecker extends StatefulWidget {
  const PermissionChecker({Key? key}) : super(key: key);

  @override
  State<PermissionChecker> createState() => _PermissionCheckerState();
}

class _PermissionCheckerState extends State<PermissionChecker> {
  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    final hasAudioPermission = androidVersion >= 30;
    final hideStopService = isAndroid &&
        bind.mainGetBuildinOption(key: kOptionHideStopService) == 'Y';
    final allowPermChangeInAcceptWindow = option2bool(
        kOptionEnablePermChangeInAcceptWindow,
        bind.mainGetBuildinOption(
          key: kOptionEnablePermChangeInAcceptWindow,
        ));
    final permissionChangeLocked = isAndroid &&
        serverModel.clients.any((c) => !c.disconnected) &&
        !allowPermChangeInAcceptWindow;
    final t = context.ex;
    final rows = <Widget>[
      if (!hideStopService || !serverModel.mediaOk)
        PermissionRow(
            translate("Screen Capture"),
            serverModel.mediaOk,
            !serverModel.mediaOk &&
                    gFFI.userModel.userName.value.isEmpty &&
                    bind.mainGetLocalOption(key: "show-scam-warning") != "N"
                ? () => showScamWarning(context, serverModel)
                : serverModel.toggleService,
            icon: Icons.screen_share_outlined),
      PermissionRow(
        translate("Input Control"),
        serverModel.inputOk,
        serverModel.toggleInput,
        icon: Icons.touch_app_outlined,
      ),
      PermissionRow(
        translate("Transfer file"),
        serverModel.fileOk,
        serverModel.toggleFile,
        enabled: !permissionChangeLocked,
        icon: Icons.folder_outlined,
      ),
      hasAudioPermission
          ? PermissionRow(translate("Audio Capture"), serverModel.audioOk,
              serverModel.toggleAudio,
              enabled: !permissionChangeLocked, icon: Icons.mic_none)
          : Padding(
              padding: const EdgeInsets.all(ExantasTokens.space4),
              child: Row(children: [
                Icon(Icons.info_outline, color: t.textSecondary),
                const SizedBox(width: ExantasTokens.space3),
                Expanded(
                    child: Text(
                  translate("android_version_audio_tip"),
                  style: Theme.of(context).textTheme.bodySmall,
                ))
              ])),
      PermissionRow(
        translate("Enable clipboard"),
        serverModel.clipboardOk,
        serverModel.toggleClipboard,
        enabled: !permissionChangeLocked,
        icon: Icons.content_paste,
      ),
    ];
    final spaced = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) spaced.add(Divider(height: 1, color: t.border));
      spaced.add(rows[i]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (serverModel.mediaOk && !hideStopService)
        Padding(
            padding: const EdgeInsets.only(bottom: ExantasTokens.space4),
            child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: t.danger),
                icon: const Icon(Icons.stop),
                onPressed: serverModel.toggleService,
                label: Text(translate("Stop service")))),
      ExSectionHeader(translate("Permissions")),
      const SizedBox(height: ExantasTokens.space2),
      Card(clipBehavior: Clip.antiAlias, child: Column(children: spaced)),
    ]);
  }
}

class PermissionRow extends StatelessWidget {
  const PermissionRow(this.name, this.isOk, this.onPressed,
      {Key? key, this.enabled = true, this.icon})
      : super(key: key);

  final String name;
  final bool isOk;
  final VoidCallback onPressed;
  final bool enabled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ExListRow(
        title: name,
        icon: icon,
        onTap: enabled ? onPressed : null,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          ExStatusPill(isOk ? ExStrings.permOn : ExStrings.permOff,
              status: isOk ? ExStatus.success : ExStatus.neutral,
              icon: isOk ? Icons.check_circle_outline : Icons.circle_outlined),
          const SizedBox(width: ExantasTokens.space2),
          Switch(
              value: isOk,
              onChanged: enabled
                  ? (bool value) {
                      onPressed();
                    }
                  : null),
        ]));
  }
}

class ConnectionManager extends StatelessWidget {
  const ConnectionManager({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    return Padding(
        padding: const EdgeInsets.only(bottom: ExantasTokens.space4),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ExSectionHeader(ExStrings.incomingConnections),
          const SizedBox(height: ExantasTokens.space2),
          if (serverModel.clients.isEmpty)
            ExCard(
                child: ExEmptyState(
                    icon: Icons.devices_other_outlined,
                    title: ExStrings.noIncoming,
                    message: ExStrings.noIncomingHint)),
          ...serverModel.clients.map((client) => Padding(
              padding: const EdgeInsets.only(bottom: ExantasTokens.space3),
              child: ExCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Row(
                      children: [
                        Expanded(child: ClientInfo(client)),
                        client.isFileTransfer || !client.authorized
                            ? const SizedBox.shrink()
                            : IconButton(
                                tooltip: ExStrings.chat,
                                onPressed: () {
                                  gFFI.chatModel.changeCurrentKey(
                                      MessageKey(client.peerId, client.id));
                                  HomePage.homeKey.currentState?.openChat();
                                },
                                icon: unreadTopRightBuilder(
                                    client.unreadChatMessageCount)),
                      ],
                    ),
                    Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: ExStatusPill(
                            translate(client.isFileTransfer
                                ? "Transfer file"
                                : "Share screen"),
                            status: ExStatus.info,
                            icon: client.isFileTransfer
                                ? Icons.folder_outlined
                                : Icons.mobile_screen_share)),
                    const SizedBox(height: ExantasTokens.space3),
                    if (!client.authorized)
                      Text(
                        translate("android_new_connection_tip"),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ).marginOnly(bottom: ExantasTokens.space3),
                    client.authorized
                        ? _buildDisconnectButton(context, client)
                        : _buildNewConnectionHint(serverModel, client),
                    if (client.incomingVoiceCall && !client.inVoiceCall)
                      ..._buildNewVoiceCallHint(context, serverModel, client),
                  ])))),
        ]));
  }

  Widget _buildDisconnectButton(BuildContext context, Client client) {
    final danger = FilledButton.styleFrom(backgroundColor: context.ex.danger);
    final disconnectButton = FilledButton.icon(
      style: danger,
      icon: const Icon(Icons.close),
      onPressed: () {
        bind.cmCloseConnection(connId: client.id);
        gFFI.invokeMethod("cancel_notification", client.id);
      },
      label: Text(translate("Disconnect")),
    );
    final buttons = [disconnectButton];
    if (client.inVoiceCall) {
      buttons.insert(
        0,
        FilledButton.icon(
          style: danger,
          icon: const Icon(Icons.phone),
          label: Text(translate("Stop")),
          onPressed: () {
            bind.cmCloseVoiceCall(id: client.id);
            gFFI.invokeMethod("cancel_notification", client.id);
          },
        ),
      );
    }

    if (buttons.length == 1) {
      return disconnectButton;
    } else {
      return Row(
        children: [
          Expanded(child: buttons[0]),
          const SizedBox(width: ExantasTokens.space2),
          Expanded(child: buttons[1]),
        ],
      );
    }
  }

  Widget _buildNewConnectionHint(ServerModel serverModel, Client client) {
    return Row(children: [
      Expanded(
          child: OutlinedButton(
              child: Text(translate("Dismiss")),
              onPressed: () {
                serverModel.sendLoginResponse(client, false);
              })),
      if (serverModel.approveMode != 'password') ...[
        const SizedBox(width: ExantasTokens.space2),
        Expanded(
            child: FilledButton.icon(
                icon: const Icon(Icons.check),
                label: Text(translate("Accept")),
                onPressed: () {
                  serverModel.sendLoginResponse(client, true);
                })),
      ],
    ]);
  }

  List<Widget> _buildNewVoiceCallHint(
      BuildContext context, ServerModel serverModel, Client client) {
    return [
      const SizedBox(height: ExantasTokens.space3),
      Text(
        translate("android_new_voice_call_tip"),
        style: Theme.of(context).textTheme.bodyMedium,
      ).marginOnly(bottom: ExantasTokens.space3),
      Row(children: [
        Expanded(
            child: OutlinedButton(
                child: Text(translate("Dismiss")),
                onPressed: () {
                  serverModel.handleVoiceCall(client, false);
                })),
        if (serverModel.approveMode != 'password') ...[
          const SizedBox(width: ExantasTokens.space2),
          Expanded(
              child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(translate("Accept")),
                  onPressed: () {
                    serverModel.handleVoiceCall(client, true);
                  })),
        ],
      ])
    ];
  }
}

class PaddingCard extends StatelessWidget {
  const PaddingCard({Key? key, required this.child, this.title, this.titleIcon})
      : super(key: key);

  final String? title;
  final Icon? titleIcon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.only(bottom: ExantasTokens.space4),
        child: ExCard(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: ExantasTokens.space3),
                  child: Row(
                    children: [
                      if (titleIcon != null)
                        titleIcon!.marginOnly(right: ExantasTokens.space3),
                      Expanded(
                        child: Semantics(
                            header: true,
                            child: Text(title!,
                                style:
                                    Theme.of(context).textTheme.titleMedium)),
                      )
                    ],
                  )),
            child,
          ],
        )));
  }
}

class ClientInfo extends StatelessWidget {
  final Client client;
  ClientInfo(this.client);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Padding(
            padding: const EdgeInsets.only(right: ExantasTokens.space3),
            child: _buildAvatar(context)),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(client.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleSmall),
          Text(client.peerId, style: text.bodySmall)
        ]))
      ],
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final fallback = CircleAvatar(
      backgroundColor: str2color(client.name,
          Theme.of(context).brightness == Brightness.light ? 255 : 150),
      child: Text(client.name.isNotEmpty ? client.name[0] : '?'),
    );
    return buildAvatarWidget(
          avatar: client.avatar,
          size: 40,
          fallback: fallback,
        ) ??
        fallback;
  }
}

void androidChannelInit() {
  gFFI.setMethodCallHandler((method, arguments) {
    debugPrint("flutter got android msg,$method,$arguments");
    try {
      switch (method) {
        case "start_capture":
          {
            gFFI.dialogManager.dismissAll();
            gFFI.serverModel.updateClientState();
            break;
          }
        case "on_state_changed":
          {
            var name = arguments["name"] as String;
            var value = arguments["value"] as String == "true";
            debugPrint("from jvm:on_state_changed,$name:$value");
            gFFI.serverModel.changeStatue(name, value);
            break;
          }
        case "on_android_permission_result":
          {
            var type = arguments["type"] as String;
            var result = arguments["result"] as bool;
            AndroidPermissionManager.complete(type, result);
            break;
          }
        case "on_media_projection_canceled":
          {
            gFFI.serverModel.stopService();
            break;
          }
        case "msgbox":
          {
            var type = arguments["type"] as String;
            var title = arguments["title"] as String;
            var text = arguments["text"] as String;
            var link = (arguments["link"] ?? '') as String;
            msgBox(gFFI.sessionId, type, title, text, link, gFFI.dialogManager);
            break;
          }
        case "stop_service":
          {
            print(
                "stop_service by kotlin, isStart:${gFFI.serverModel.isStart}");
            if (gFFI.serverModel.isStart) {
              gFFI.serverModel.stopService();
            }
            break;
          }
      }
    } catch (e) {
      debugPrintStack(label: "MethodCallHandler err:$e");
    }
    return "";
  });
}

void showScamWarning(BuildContext context, ServerModel serverModel) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return ScamWarningDialog(serverModel: serverModel);
    },
  );
}
