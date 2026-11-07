import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/pages/server_page.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/web/settings_page.dart';
import 'package:get/get.dart';
import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import '../ui/exantas_strings.dart';
import 'connection_page.dart';
import 'exantas_support_page.dart';
import 'home_destinations.dart';

abstract class PageShape extends Widget {
  final String title = "";
  final Widget icon = Icon(null);
  final List<Widget> appBarActions = [];
}

class HomePage extends StatefulWidget {
  static final homeKey = GlobalKey<HomePageState>();

  HomePage() : super(key: homeKey);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  var _selectedIndex = 0;
  int get selectedIndex => _selectedIndex;
  final List<PageShape> _pages = [];
  List<HomeDestination> _destinations = [];
  ChatPage? _chatPage;
  // Chat is no longer a root tab: it is a sub-view of the Share destination.
  bool _chatOpen = false;
  bool get isChatPageCurrentTab => isAndroid
      ? _chatOpen && _destinations[_selectedIndex] == HomeDestination.share
      : false; // change this when ios have chat page

  void refreshPages() {
    setState(() {
      initPages();
    });
  }

  @override
  void initState() {
    super.initState();
    initPages();
  }

  void initPages() {
    _pages.clear();
    _chatPage = null;
    _destinations = homeDestinations(
        isAndroid: isAndroid,
        incomingOnly: bind.isIncomingOnly(),
        outgoingOnly: bind.isOutgoingOnly());
    for (final d in _destinations) {
      switch (d) {
        case HomeDestination.home:
          _pages.add(ExantasSupportPage(
              view: ExantasSupportView.home, onOpenWork: _openWork));
          break;
        case HomeDestination.work:
          _pages.add(ExantasSupportPage(
              view: ExantasSupportView.work, onOpenWork: _openWork));
          break;
        case HomeDestination.connection:
          _pages.add(ConnectionPage(appBarActions: []));
          break;
        case HomeDestination.share:
          _chatPage = ChatPage(type: ChatPageType.mobileMain);
          _pages.add(ServerPage());
          break;
        case HomeDestination.settings:
          _pages.add(SettingsPage());
          break;
      }
    }
    if (_selectedIndex >= _pages.length) _selectedIndex = 0;
    // Chat only lives inside Share: leave it when Share is gone/not selected.
    if (_chatPage == null ||
        _destinations[_selectedIndex] != HomeDestination.share) {
      _chatOpen = false;
    }
  }

  void _openWork() {
    final i = _destinations.indexOf(HomeDestination.work);
    if (i >= 0) _select(i);
  }

  void _select(int index) {
    setState(() {
      if (_selectedIndex == index) {
        _chatOpen = false; // re-selecting Share returns to the sessions list
        return;
      }
      _selectedIndex = index;
      _chatOpen = false;
    });
  }

  /// Opens chat inside Share, closing the chat overlay and clearing unread
  /// exactly as the former chat tab did.
  void openChat() {
    final i = _destinations.indexOf(HomeDestination.share);
    if (i < 0 || _chatPage == null) return;
    setState(() {
      _selectedIndex = i;
      _chatOpen = true;
    });
    gFFI.chatModel.hideChatIconOverlay();
    gFFI.chatModel.hideChatWindowOverlay();
    gFFI.chatModel.mobileClearClientUnread(gFFI.chatModel.currentKey.connId);
  }

  Widget _destIcon(int index, bool selected) {
    final d = _destinations[index];
    if (d == HomeDestination.connection) return _pages[index].icon;
    final icon = Icon(selected ? d.selectedIcon : d.icon);
    if (d != HomeDestination.share || _chatPage == null) return icon;
    return Obx(() {
      final unread = gFFI.chatModel.mobileUnreadSum.value;
      return Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          child: icon);
    });
  }

  String _destLabel(int index) => _destinations[index] == HomeDestination.connection
      ? _pages[index].title
      : _destinations[index].label;

  List<Widget> _appBarActions() {
    if (_chatOpen) return _chatPage!.appBarActions;
    final actions = _pages[_selectedIndex].appBarActions;
    if (_destinations[_selectedIndex] != HomeDestination.share ||
        _chatPage == null) {
      return actions;
    }
    return [
      IconButton(
          key: const ValueKey('share-open-chat'),
          tooltip: ExStrings.chat,
          icon: unreadTopRightBuilder(gFFI.chatModel.mobileUnreadSum),
          onPressed: openChat),
      ...actions,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = useNavigationRail(size);
    final body = _chatOpen ? _chatPage! : _pages.elementAt(_selectedIndex);
    return PopScope(
        canPop: _selectedIndex == 0 && !_chatOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          setState(() {
            if (_chatOpen) {
              _chatOpen = false;
            } else {
              _selectedIndex = 0;
            }
          });
        },
        child: Scaffold(
          appBar: AppBar(
            centerTitle: true,
            leading: _chatOpen
                ? BackButton(onPressed: () => setState(() => _chatOpen = false))
                : null,
            title: appTitle(),
            actions: _appBarActions(),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  key: navigationBarKey,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _select,
                  destinations: [
                    for (var i = 0; i < _pages.length; i++)
                      NavigationDestination(
                          icon: _destIcon(i, false),
                          selectedIcon: _destIcon(i, true),
                          label: _destLabel(i)),
                  ],
                ),
          body: wide
              ? Row(children: [
                  SafeArea(
                    right: false,
                    child: NavigationRail(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _select,
                      labelType: size.height < 560
                          ? NavigationRailLabelType.selected
                          : NavigationRailLabelType.all,
                      destinations: [
                        for (var i = 0; i < _pages.length; i++)
                          NavigationRailDestination(
                              icon: _destIcon(i, false),
                              selectedIcon: _destIcon(i, true),
                              label: Text(_destLabel(i))),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ])
              : body,
        ));
  }

  Widget appTitle() {
    final currentUser = gFFI.chatModel.currentUser;
    final currentKey = gFFI.chatModel.currentKey;
    if (isChatPageCurrentTab &&
        currentUser != null &&
        currentKey.peerId.isNotEmpty) {
      final connected =
          gFFI.serverModel.clients.any((e) => e.id == currentKey.connId);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Tooltip(
            message: currentKey.isOut
                ? translate('Outgoing connection')
                : translate('Incoming connection'),
            child: Icon(
              currentKey.isOut
                  ? Icons.call_made_rounded
                  : Icons.call_received_rounded,
            ),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "${currentUser.firstName}   ${currentUser.id}",
                  ),
                  if (connected)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromARGB(255, 133, 246, 199)),
                    ).marginSymmetric(horizontal: 2),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Text(bind.mainGetAppNameSync());
  }
}

class WebHomePage extends StatelessWidget {
  final connectionPage =
      ConnectionPage(appBarActions: <Widget>[const WebSettingsPage()]);

  @override
  Widget build(BuildContext context) {
    stateGlobal.isInMainPage = true;
    handleUnilink(context);
    return Scaffold(
      // backgroundColor: MyTheme.grayBg,
      appBar: AppBar(
        centerTitle: true,
        title: Text("${bind.mainGetAppNameSync()} (Preview)"),
        actions: connectionPage.appBarActions,
      ),
      body: connectionPage,
    );
  }

  handleUnilink(BuildContext context) {
    if (webInitialLink.isEmpty) {
      return;
    }
    final link = webInitialLink;
    webInitialLink = '';
    final splitter = ["/#/", "/#", "#/", "#"];
    var fakelink = '';
    for (var s in splitter) {
      if (link.contains(s)) {
        var list = link.split(s);
        if (list.length < 2 || list[1].isEmpty) {
          return;
        }
        list.removeAt(0);
        fakelink = "rustdesk://${list.join(s)}";
        break;
      }
    }
    if (fakelink.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(fakelink);
    if (uri == null) {
      return;
    }
    final args = urlLinkToCmdArgs(uri);
    if (args == null || args.isEmpty) {
      return;
    }
    bool isFileTransfer = false;
    bool isViewCamera = false;
    bool isTerminal = false;
    String? id;
    String? password;
    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--connect':
        case '--play':
          id = args[i + 1];
          i++;
          break;
        case '--file-transfer':
          isFileTransfer = true;
          id = args[i + 1];
          i++;
          break;
        case '--view-camera':
          isViewCamera = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal':
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal-admin':
          setEnvTerminalAdmin();
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--password':
          password = args[i + 1];
          i++;
          break;
        default:
          break;
      }
    }
    if (id != null) {
      connect(context, id, 
        isFileTransfer: isFileTransfer, 
        isViewCamera: isViewCamera, 
        isTerminal: isTerminal,
        password: password);
    }
  }
}
