package com.zephyr.app.ui.nav

import com.zephyr.design.components.ZToast
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.activity.ActivitySheet
import com.zephyr.app.ui.activity.TraceSheet
import com.zephyr.app.ui.command.CommandAction
import com.zephyr.app.ui.command.CommandOverlay
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
@Serializable data class Nodes(val query: String = "", val back: String = "资料库")
@Serializable data class Rules(val query: String = "", val back: String = "资料库")
@Serializable data class Subs(val back: String = "资料库")
@Serializable data class SettingsRoute(val back: String = "资料库")
@Serializable object Today
@Serializable object Onboarding

/** Root: theme from settings, nav graph, and the home-level overlays (library, scene, activity, command, import). */
@Composable
fun AppRoot(onToggle: (Boolean) -> Unit, startOnboarding: Boolean) {
    val settings by AppGraph.engine.settings().collectAsState(Settings())
    val dark = when (settings.appearance) { Appearance.SYSTEM -> isSystemInDarkTheme(); Appearance.DARK -> true; Appearance.LIGHT -> false }
    ZephyrTheme(dark = dark, accent = ZAccent.valueOf(settings.accent.name)) {
        val nav = rememberNavController()
        var library by remember { mutableStateOf(false) }
        val backTo: (String) -> Unit = { label -> nav.popBackStack(); if (label == "资料库") library = true }
        var scene by remember { mutableStateOf<Scene?>(null) }
        var activity by remember { mutableStateOf(false) }
        var traceHost by remember { mutableStateOf<String?>(null) }
        var command by remember { mutableStateOf(false) }
        var import by remember { mutableStateOf(false) }
        val home: HomeViewModel = viewModel { HomeViewModel() }

        Box(Modifier.fillMaxSize().background(ZTheme.colors.bg)) {
            NavHost(
                nav, startDestination = if (startOnboarding) Onboarding else Home,
                enterTransition = { slideInHorizontally(ZAnim.slow()) { it / 4 } + fadeIn(ZAnim.standard()) },
                exitTransition = { fadeOut(ZAnim.micro()) },
                popEnterTransition = { fadeIn(ZAnim.standard()) },
                popExitTransition = { slideOutHorizontally(ZAnim.standard()) { it / 4 } + fadeOut(ZAnim.standard()) },
            ) {
                composable<Home> {
                    HomeScreen(
                        home,
                        HomeActions(
                            onToggle = onToggle,
                            onSettings = { nav.navigate(SettingsRoute(back = "首页")) },
                            onLibrary = { library = true },
                            onCommand = { command = true },
                            onToday = { nav.navigate(Today) },
                            onSubscriptions = { nav.navigate(Subs(back = "首页")) },
                            onScene = { scene = it },
                            onChangeGlobalNode = { nav.navigate(Nodes(back = "首页")) },
                            onActivity = { activity = true },
                        ),
                    )
                }
                // Back returns where the page was opened from; from the library it reopens the library (prototype 1287).
                composable<Nodes> { e -> val r = e.toRoute<Nodes>(); NodesScreen(viewModel { NodesViewModel() }, r.query, back = r.back, onBack = { backTo(r.back) }, onImport = { import = true }) }
                composable<Rules> { e -> val r = e.toRoute<Rules>(); RulesScreen(r.query, back = r.back) { backTo(r.back) } }
                composable<Subs> { e -> val r = e.toRoute<Subs>(); SubscriptionsScreen(back = r.back, onBack = { backTo(r.back) }, onImport = { import = true }) }
                composable<SettingsRoute> { e -> val r = e.toRoute<SettingsRoute>(); SettingsScreen(r.back) { backTo(r.back) } }
                composable<Today>(
                    enterTransition = { slideInVertically(ZAnim.slow()) { it / 3 } + fadeIn(ZAnim.standard()) },
                    popExitTransition = { slideOutVertically(ZAnim.standard()) { it / 3 } + fadeOut(ZAnim.standard()) },
                ) { TodayScreen { nav.popBackStack() } }
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
                    LibraryDest.Settings, LibraryDest.TrustedWifi, LibraryDest.LocalProxy, LibraryDest.Widgets -> nav.navigate(SettingsRoute())
                }
            }
            val scenesNow by home.scenes.collectAsStateWithLifecycle()
            SceneSheet(
                scene?.let { s -> scenesNow.firstOrNull { it.id == s.id } ?: s },
                onDismiss = { scene = null },
                onPick = { s, n -> scene = null; home.pick(s, n) },
                onSource = { s, src -> home.setSource(s, src); if (s.kind == com.zephyr.engine.SceneKind.AI && src == com.zephyr.engine.SceneSource.AUTO) scene = null },
            )
            ActivitySheet(activity, { activity = false }) { traceHost = it }
            TraceSheet(traceHost) { traceHost = null }
            ImportSheet(import, { import = false }) { import = false }
            // Toasts sit above every sheet and the command layer, so an undo or a failover notice is never hidden.
            val toast by home.toast.collectAsStateWithLifecycle()
            ZToast(
                visible = toast != null,
                message = toast?.message ?: "",
                action = if (toast?.let { it.undoAction != null || (it.sceneId != null && it.previousNodeId != null) } == true) "撤销" else null,
                onAction = { home.undo() },
                modifier = Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 84.dp).zIndex(10f),
            )
            CommandOverlay(command, { command = false }) { a ->
                command = false
                when (a) {
                    is CommandAction.TestRule -> nav.navigate(Rules(a.input, back = "首页"))
                    is CommandAction.OpenNodes -> nav.navigate(Nodes(a.query, back = "首页"))
                    is CommandAction.Apply -> home.applyCommand(a.plan)
                }
            }
        }
    }
}
