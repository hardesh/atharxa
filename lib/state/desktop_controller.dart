import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nativeapi_flutter/nativeapi_flutter.dart' hide AppInfo;

import '../app_info.dart';
import '../ui/format.dart';
import 'core_providers.dart';
import 'sync_controller.dart';

/// macOS background behaviour (You › Device sync › "On this Mac").
@immutable
class DesktopState {
  const DesktopState({
    this.supported = false,
    this.launchAtLoginSupported = false,
    this.launchAtLogin = false,
    this.menuBar = true,
  });

  /// True on macOS only.
  final bool supported, launchAtLoginSupported, launchAtLogin, menuBar;

  DesktopState copyWith({bool? launchAtLogin, bool? menuBar}) => DesktopState(
    supported: supported,
    launchAtLoginSupported: launchAtLoginSupported,
    launchAtLogin: launchAtLogin ?? this.launchAtLogin,
    menuBar: menuBar ?? this.menuBar,
  );
}

/// Started once from `main` (like sync); a no-op off macOS.
final desktopControllerProvider = NotifierProvider<DesktopController, DesktopState>(DesktopController.new);

/// macOS window and background behaviour, all through `nativeapi` (Dart FFI,
/// no Swift of our own):
/// * title bar blended into the app, minimum window size (DESIGN.md §2),
/// * while sync is on, closing the window hides it so sync keeps running;
///   clicking the Dock icon brings it back,
/// * a menu bar item with sync status, Sync now, Open and Quit,
/// * optional open at login (SMAppService under the hood).
///
/// App Nap is disabled in Info.plist (`NSAppSleepDisabled`).
class DesktopController extends Notifier<DesktopState> {
  static const _menuBarKey = 'desktop_menu_bar';
  static const _trayIcon = 'assets/tray/sync_template.png';

  Window? _window;
  TrayIcon? _tray;
  MenuItem? _statusItem;
  LaunchAtLogin? _login;

  @override
  DesktopState build() {
    if (!Platform.isMacOS) return const DesktopState();
    final prefs = ref.watch(prefsProvider);
    _setUpWindow();
    _login = LaunchAtLogin.isSupported() ? LaunchAtLogin.create() : null;
    _login?.setProgram(Platform.resolvedExecutable, const []);
    ref.listen(syncControllerProvider, (_, s) => _updateTray(s));
    ref.onDispose(() => _tray?.dispose());
    final initial = DesktopState(
      supported: true,
      launchAtLoginSupported: _login != null,
      launchAtLogin: _login?.isEnabled ?? false,
      menuBar: prefs.getBool(_menuBarKey) ?? true,
    );
    Future.microtask(() => _updateTray(ref.read(syncControllerProvider)));
    return initial;
  }

  void _setUpWindow() {
    final w = _window = WindowManager.instance.getCurrent();
    if (w == null) return;
    w.titleBarStyle = TitleBarStyle.hidden;
    w.minimumSize = const Size(900, 640).toNative();
    w.addListener((e) {
      // Keep running in the background while sync is on.
      if (e is WindowCloseRequestedEvent && ref.read(syncControllerProvider).enabled) {
        e.request.cancel();
        w.hide();
      }
    });
    Application.instance.addListener((e) {
      if (e is ApplicationActivatedEvent && !w.isVisible) showWindow();
    });
  }

  void showWindow() {
    _window
      ?..show()
      ..focus();
  }

  Future<void> setLaunchAtLogin(bool on) async {
    final l = _login;
    if (l == null) return;
    on ? l.enable() : l.disable();
    state = state.copyWith(launchAtLogin: l.isEnabled);
  }

  Future<void> setMenuBar(bool on) async {
    await ref.read(prefsProvider).setBool(_menuBarKey, on);
    state = state.copyWith(menuBar: on);
    _updateTray(ref.read(syncControllerProvider));
  }

  void _updateTray(SyncState s) {
    final visible = s.enabled && (stateOrNull?.menuBar ?? true);
    if (!visible) {
      _tray?.setVisible(false);
      return;
    }
    final tray = _tray ??= _createTray();
    if (tray == null) return;
    final last = s.lastSync;
    final status = s.busy ? 'Syncing…' : (last == null ? 'Not synced yet' : 'Synced ${fmtWhen(last)}');
    _statusItem?.label = status;
    tray.setTooltip('${AppInfo.name} · $status');
    tray.setVisible(true);
  }

  TrayIcon? _createTray() {
    final tray = TrayIcon.create();
    if (tray == null) return null;
    tray.icon = ImageAsset.fromAsset(_trayIcon);
    tray.isIconTemplate = true; // tinted for light/dark menu bars

    final menu = Menu.create()!;
    MenuItem item(String label, void Function() onClick) {
      final i = MenuItem.createWithLabelAndType(label, MenuItemType.normal)!;
      i.addListener((e) {
        if (e is MenuItemClickedEvent) onClick();
      });
      menu.addItem(i);
      return i;
    }

    // Status line ("Synced today, 13:12"); clicking it opens the window.
    _statusItem = item('', showWindow);
    menu.addSeparator();
    item('Sync now', () => ref.read(syncControllerProvider.notifier).syncNow());
    item('Open ${AppInfo.name}', showWindow);
    menu.addSeparator();
    item('Quit ${AppInfo.name}', () => exit(0));

    tray.setContextMenu(menu);
    tray.setContextMenuTrigger(ContextMenuTrigger.clicked);
    return tray;
  }
}
