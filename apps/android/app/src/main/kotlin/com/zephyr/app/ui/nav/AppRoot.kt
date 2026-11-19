package com.zephyr.app.ui.nav

import com.zephyr.design.components.ZToast
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.zIndex
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.ui.Alignment
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.activity.ActivitySheet
import com.zephyr.app.ui.command.CommandAction
import com.zephyr.app.ui.command.CommandOverlay
import com.zephyr.app.ui.common.BackTo
import com.zephyr.app.ui.common.resolve
import com.zephyr.app.ui.home.HomeActions
import com.zephyr.app.ui.home.HomeScreen
import com.zephyr.app.ui.home.HomeViewModel
import com.zephyr.app.ui.library.LibraryDest
import com.zephyr.app.ui.library.LibrarySheet
import com.zephyr.app.ui.nodes.NodesScreen
import com.zephyr.app.ui.nodes.NodesViewModel
import com.zephyr.app.ui.onboarding.OnboardingScreen
import com.zephyr.app.ui.rules.RulesScreen
import com.zephyr.app.ui.scene.SceneSheet
import com.zephyr.app.ui.settings.SettingsScreen
import com.zephyr.app.ui.subs.ImportSheet
import com.zephyr.app.ui.subs.SubscriptionsScreen
import com.zephyr.app.ui.today.TodayScreen
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import com.zephyr.design.theme.ZephyrTheme
import com.zephyr.design.tokens.ZAccent
import com.zephyr.engine.Appearance
import com.zephyr.engine.ProxyMode
import com.zephyr.engine.Scene
import com.zephyr.engine.Settings
import kotlinx.serialization.Serializable
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

@Serializable object Home
@Serializable data class Nodes(val query: String = "", val back: BackTo = BackTo.LIBRARY)
@Serializable data class Rules(val query: String = "", val back: BackTo = BackTo.LIBRARY)
@Serializable data class Subs(val back: BackTo = BackTo.LIBRARY)
@Serializable data class SettingsRoute(val back: BackTo = BackTo.LIBRARY)
@Serializable object Logs
@Serializable object Licenses
@Serializable data class TrustedWifiRoute(val back: BackTo = BackTo.LIBRARY)
@Serializable data class LocalProxyRoute(val back: BackTo = BackTo.LIBRARY)
@Serializable data class WidgetsRoute(val back: BackTo = BackTo.LIBRARY)
@Serializable object Today
@Serializable object Onboarding

/** Root: theme from settings, nav graph, and the home-level overlays (library, scene, activity, command, import). */
@Composable
fun AppRoot(onToggle: (Boolean) -> Unit, startOnboarding: Boolean, pendingImport: String? = null, onImportShown: () -> Unit = {}) {
    val settings by AppGraph.engine.settings().collectAsState(Settings())
    val dark = when (settings.appearance) { Appearance.SYSTEM -> isSystemInDarkTheme(); Appearance.DARK -> true; Appearance.LIGHT -> false }
    // System bar icons follow the App's appearance, not the system's (review A-P1-1): a forced light App on a dark
    // system would otherwise draw white status icons on #F2F2F7.
    val view = androidx.compose.ui.platform.LocalView.current
    if (!view.isInEditMode) {
        androidx.compose.runtime.SideEffect {
            val window = (view.context as? android.app.Activity)?.window ?: return@SideEffect
            androidx.core.view.WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !dark
                isAppearanceLightNavigationBars = !dark
            }
        }
    }
    // Review H-P2-5: the scrub coach line retires for good after the first scrub. Start as seen so it never flashes.
    val scrubSeen by remember { if (AppGraph.hasSettings) AppGraph.settings.scrubHintSeen else kotlinx.coroutines.flow.flowOf(true) }.collectAsState(true)
    val hintScope = androidx.compose.runtime.rememberCoroutineScope()
    val scrubHint = remember(scrubSeen) { com.zephyr.app.ui.common.ScrubHint(scrubSeen) { if (AppGraph.hasSettings) hintScope.launch { AppGraph.settings.setScrubHintSeen() } } }
    ZephyrTheme(dark = dark, accent = ZAccent.valueOf(settings.accent.name)) {
        androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalScrubHint provides scrubHint) {
        val nav = rememberNavController()
        // Review A-P2-4: overlays survive rotation / fold / process death.
        var library by rememberSaveable { mutableStateOf(false) }
        val backTo: (BackTo) -> Unit = { to -> nav.popBackStack(); if (to == BackTo.LIBRARY) library = true }
        var scene by remember { mutableStateOf<Scene?>(null) }
        var activity by rememberSaveable { mutableStateOf(false) }
        var traceHost by rememberSaveable { mutableStateOf<String?>(null) }
        var command by rememberSaveable { mutableStateOf(false) }
        var import by rememberSaveable { mutableStateOf(false) }
        var importPrefill by rememberSaveable { mutableStateOf<String?>(null) }
        // A deep link only opens the sheet listing what it would add; the user still taps 添加 (review A-P1-4, U26).
        androidx.compose.runtime.LaunchedEffect(pendingImport) {
            if (pendingImport != null) { importPrefill = pendingImport; import = true; onImportShown() }
        }
        val home: HomeViewModel = viewModel { HomeViewModel() }

        // Review H-P2-11: 原型 --cmdbg .72 + blur 30。API 31+ 模糊指令层下面的页面；更低版本 blur 无效，遮罩保持 .86。
        val cmdBlur by androidx.compose.animation.core.animateDpAsState(if (command) 30.dp else 0.dp, ZAnim.standard(), label = "cmdBlur")
        // Push slides in from the end edge, pop returns toward it: mirrored in RTL (slide offsets are absolute px).
        val dir = com.zephyr.app.ui.common.startToEndSign()
        Box(Modifier.fillMaxSize().background(ZTheme.colors.bg)) {
            NavHost(
                nav, startDestination = if (startOnboarding) Onboarding else Home,
                modifier = if (cmdBlur > 0.dp) Modifier.blur(cmdBlur) else Modifier,
                enterTransition = { slideInHorizontally(ZAnim.slow()) { dir * it / 4 } + fadeIn(ZAnim.standard()) },
                // Review A-P2-8: the page underneath moves too, so a predictive-back drag (which seeks these
                // transitions) previews it sliding back in from the left instead of a flat cross-fade.
                exitTransition = { slideOutHorizontally(ZAnim.slow()) { -dir * it / 10 } + fadeOut(ZAnim.standard()) },
                popEnterTransition = { slideInHorizontally(ZAnim.standard()) { -dir * it / 10 } + fadeIn(ZAnim.standard()) },
                popExitTransition = { slideOutHorizontally(ZAnim.standard()) { dir * it / 4 } + fadeOut(ZAnim.standard()) },
            ) {
                composable<Home> {
                    HomeScreen(
                        home,
                        HomeActions(
                            onToggle = onToggle,
                            onSettings = { nav.navigate(SettingsRoute(back = BackTo.HOME)) },
                            onLibrary = { library = true },
                            onCommand = { command = true },
                            onToday = { nav.navigate(Today) },
                            onSubscriptions = { nav.navigate(Subs(back = BackTo.HOME)) },
                            onScene = { scene = it },
                            onChangeGlobalNode = { nav.navigate(Nodes(back = BackTo.HOME)) },
                            onActivity = { activity = true },
                        ),
                    )
                }
                // Back returns where the page was opened from; from the library it reopens the library (prototype 1287).
                composable<Nodes> { e -> val r = e.toRoute<Nodes>(); NodesScreen(viewModel { NodesViewModel() }, r.query, back = r.back, onBack = { backTo(r.back) }, onImport = { import = true }) }
                composable<Rules> { e -> val r = e.toRoute<Rules>(); RulesScreen(r.query, back = r.back) { backTo(r.back) } }
                composable<Subs> { e -> val r = e.toRoute<Subs>(); SubscriptionsScreen(back = r.back, onBack = { backTo(r.back) }, onImport = { import = true }, onNotice = { home.notify(it) }) }
                composable<SettingsRoute> { e -> val r = e.toRoute<SettingsRoute>(); SettingsScreen(
                    r.back, onLogs = { nav.navigate(Logs) }, onLicenses = { nav.navigate(Licenses) },
                    onTrustedWifi = { nav.navigate(TrustedWifiRoute(BackTo.SETTINGS)) }, onLocalProxy = { nav.navigate(LocalProxyRoute(BackTo.SETTINGS)) },
                ) { backTo(r.back) } }
                // Audit #208 U10: the library's three shortcuts open their own pages (iOS LibrarySheet subpages).
                composable<TrustedWifiRoute> { e -> val r = e.toRoute<TrustedWifiRoute>(); com.zephyr.app.ui.library.TrustedWifiScreen(r.back) { backTo(r.back) } }
                composable<LocalProxyRoute> { e -> val r = e.toRoute<LocalProxyRoute>(); com.zephyr.app.ui.library.LocalProxyScreen(r.back) { backTo(r.back) } }
                composable<WidgetsRoute> { e -> val r = e.toRoute<WidgetsRoute>(); com.zephyr.app.ui.library.WidgetsScreen(r.back) { backTo(r.back) } }
                composable<Logs> { com.zephyr.app.ui.settings.LogsScreen { nav.popBackStack() } }
                composable<Licenses> { com.zephyr.app.ui.settings.LicensesScreen { nav.popBackStack() } }
                composable<Today>(
                    enterTransition = { slideInVertically(ZAnim.slow()) { it / 3 } + fadeIn(ZAnim.standard()) },
                    popExitTransition = { slideOutVertically(ZAnim.standard()) { it / 3 } + fadeOut(ZAnim.standard()) },
                ) {
                    // 今日 is always a black page (review H-P2-13): run its buttons and text on the dark palette.
                    ZephyrTheme(dark = true, accent = ZAccent.valueOf(settings.accent.name)) { TodayScreen { nav.popBackStack() } }
                }
                composable<Onboarding>(enterTransition = { EnterTransition.None }, exitTransition = { ExitTransition.None }) {
                    OnboardingScreen { nav.navigate(Home) { popUpTo(Onboarding) { inclusive = true } } }
                }
            }

            val rootScope = androidx.compose.runtime.rememberCoroutineScope()
            LibrarySheet(library, { library = false }) { d ->
                library = false
                when (d) {
                    LibraryDest.Nodes -> nav.navigate(Nodes())
                    LibraryDest.Subscriptions -> nav.navigate(Subs())
                    LibraryDest.Rules -> nav.navigate(Rules())
                    // scenes is WhileSubscribed: when home is not composed .value can be empty, so subscribe once.
                    LibraryDest.Scenes -> rootScope.launch {
                        scene = home.scenes.value.firstOrNull()
                            ?: kotlinx.coroutines.withTimeoutOrNull(2_000) { home.scenes.first { it.isNotEmpty() } }?.firstOrNull()
                    }
                    LibraryDest.Settings -> nav.navigate(SettingsRoute())
                    LibraryDest.TrustedWifi -> nav.navigate(TrustedWifiRoute())
                    LibraryDest.LocalProxy -> nav.navigate(LocalProxyRoute())
                    LibraryDest.Widgets -> nav.navigate(WidgetsRoute())
                }
            }
            val scenesNow by home.scenes.collectAsStateWithLifecycle()
            val retestingNow by home.retesting.collectAsStateWithLifecycle()
            SceneSheet(
                scene?.let { s -> scenesNow.firstOrNull { it.id == s.id } ?: s },
                onDismiss = { scene = null },
                onPick = { s, n -> scene = null; home.pick(s, n) },
                onSource = { s, src -> home.setSource(s, src); if (s.kind == com.zephyr.engine.SceneKind.AI && src == com.zephyr.engine.SceneSource.AUTO) scene = null },
                retesting = scene?.id in retestingNow,
                onRetest = { s -> home.retest(s.id) },
            )
            ActivitySheet(activity, { activity = false; traceHost = null }, traceHost, onNotice = { home.notify(it) }, onUndoable = { m, u -> home.notifyUndo(m, u) }) { traceHost = it }
            ImportSheet(import, { import = false; importPrefill = null }, deepLink = importPrefill) { import = false; importPrefill = null; home.notify(it) }
            // Toasts sit above every sheet and the command layer, so an undo or a failover notice is never hidden.
            val toast by home.toast.collectAsStateWithLifecycle()
            val a11y = androidx.compose.ui.platform.LocalAccessibilityManager.current
            val window = remember(a11y) {
                val base = com.zephyr.design.tokens.ZMotion.undoWindow.toLong()
                a11y?.calculateRecommendedTimeoutMillis(base, containsIcons = false, containsText = true, containsControls = true) ?: base
            }
            LaunchedEffect(window) { home.toastWindowMs = window }
            ZToast(
                visible = toast != null,
                message = toast?.message?.resolve() ?: "",
                action = if (toast?.let { it.undoAction != null || (it.sceneId != null && it.previousNodeId != null) } == true) stringResource(R.string.common_undo) else null,
                onAction = { home.undo() },
                durationMs = window,
                key = toast?.serial,
                modifier = Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 84.dp).zIndex(10f),
            )
            CommandOverlay(command, { command = false }) { a ->
                command = false
                when (a) {
                    is CommandAction.TestRule -> nav.navigate(Rules(a.input, back = BackTo.HOME))
                    is CommandAction.OpenNodes -> nav.navigate(Nodes(a.query, back = BackTo.HOME))
                    is CommandAction.Apply -> home.applyCommand(a.plan)
                }
            }
        }
    }
    }
}
