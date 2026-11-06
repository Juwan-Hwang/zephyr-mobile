package com.zephyr.app.ui.nav

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
import com.zephyr.engine.CommandKind
import com.zephyr.engine.ProxyMode
import com.zephyr.engine.Scene
import com.zephyr.engine.Settings
import kotlinx.serialization.Serializable

@Serializable object Home
@Serializable data class Nodes(val query: String = "")
@Serializable data class Rules(val query: String = "")
@Serializable object Subs
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
        var scene by remember { mutableStateOf<Scene?>(null) }
        var activity by remember { mutableStateOf(false) }
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
                            onSubscriptions = { nav.navigate(Subs) },
                            onScene = { scene = it },
                            onChangeGlobalNode = { nav.navigate(Nodes()) },
                        ),
                    )
                }
                composable<Nodes> { e -> NodesScreen(viewModel { NodesViewModel() }, e.toRoute<Nodes>().query) { nav.popBackStack() } }
                composable<Rules> { e -> RulesScreen(e.toRoute<Rules>().query) { nav.popBackStack() } }
                composable<Subs> { SubscriptionsScreen(onBack = { nav.popBackStack() }, onImport = { import = true }) }
                composable<SettingsRoute> { e -> SettingsScreen(e.toRoute<SettingsRoute>().back) { nav.popBackStack() } }
                composable<Today>(
                    enterTransition = { slideInVertically(ZAnim.slow()) { it / 3 } + fadeIn(ZAnim.standard()) },
                    popExitTransition = { slideOutVertically(ZAnim.standard()) { it / 3 } + fadeOut(ZAnim.standard()) },
                ) { TodayScreen { nav.popBackStack() } }
                composable<Onboarding>(enterTransition = { EnterTransition.None }, exitTransition = { ExitTransition.None }) {
                    OnboardingScreen { nav.navigate(Home) { popUpTo(Onboarding) { inclusive = true } } }
                }
            }

            LibrarySheet(library, { library = false }) { d ->
                library = false
                when (d) {
                    LibraryDest.Nodes -> nav.navigate(Nodes())
                    LibraryDest.Subscriptions -> nav.navigate(Subs)
                    LibraryDest.Rules -> nav.navigate(Rules())
                    LibraryDest.Scenes -> scene = home.scenes.value.firstOrNull()
                    LibraryDest.Settings, LibraryDest.TrustedWifi, LibraryDest.LocalProxy, LibraryDest.Widgets -> nav.navigate(SettingsRoute())
                }
            }
            SceneSheet(scene) { scene = null }
            ActivitySheet(activity) { activity = false }
            ImportSheet(import, { import = false }) { import = false }
            CommandOverlay(command, { command = false }) { s ->
                command = false
                when (s.kind) {
                    CommandKind.TEST_RULE -> nav.navigate(Rules(s.payload))
                    CommandKind.OPEN_NODE_QUERY -> nav.navigate(Nodes(s.payload))
                    CommandKind.SWITCH_MODE -> home.setMode(ProxyMode.valueOf(s.payload.uppercase()))
                    CommandKind.TOGGLE_CONNECTION -> AppGraph.connection.toggle()
                    CommandKind.OPEN_PAGE -> library = true
                    CommandKind.SWITCH_NODE -> {
                        val (sceneId, id) = s.payload.split(":").let { it[0] to it[1].toLong() }
                        home.applyCommandSwitch(sceneId, id, s.subtitle?.substringAfter("将使用 ")?.removeSuffix("。") ?: s.title)
                    }
                }
            }
        }
    }
}
