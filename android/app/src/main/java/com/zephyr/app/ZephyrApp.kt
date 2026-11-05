package com.zephyr.app

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.zephyr.ui.theme.AppAccent
import com.zephyr.ui.theme.AppBadge
import com.zephyr.ui.theme.AppButton
import com.zephyr.ui.theme.AppCard
import com.zephyr.ui.theme.AppColors
import com.zephyr.ui.theme.AppEasing
import com.zephyr.ui.theme.AppGlass
import com.zephyr.ui.theme.AppInput
import com.zephyr.ui.theme.AppRadius
import com.zephyr.ui.theme.AppSpacing
import com.zephyr.ui.theme.AppSwitch
import com.zephyr.ui.theme.AppTime

// ── Accent theme composition local ────────────────────────────────────────

val LocalAccentTheme = compositionLocalOf { AppAccent.purple }

// ── Navigation destinations ──────────────────────────────────────────────

enum class ZephyrScreen(val label: String, val icon: ImageVector) {
    Home("Home", Icons.Filled.Home),
    Proxies("Proxies", Icons.Filled.ArrowForward),
    Profiles("Profiles", Icons.Filled.List),
    Logs("Logs", Icons.Filled.Terminal),
    Settings("Settings", Icons.Filled.Settings),
}

// ── Page background colors ────────────────────────────────────────────────

private val PageBgDark = Color(0xFF18181B)
private val PageBgLight = Color(0xFFF8FAFC)

// ── Main app scaffold ────────────────────────────────────────────────────

@Composable
fun ZephyrApp(
    vm: ZephyrViewModel = viewModel(),
    onRequestVpnPermission: () -> Unit = {},
) {
    var selectedTab by remember { mutableIntStateOf(0) }
    val screens = ZephyrScreen.entries
    val isDark = isSystemInDarkTheme()
    val accent = LocalAccentTheme.current

    val pageBg = if (isDark) PageBgDark else PageBgLight

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(pageBg),
    ) {
        // Page content
        Column(
            modifier = Modifier.fillMaxSize(),
        ) {
            // Top bar
            GlassTopBar(vm, accent, isDark)

            // Page content
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
            ) {
                when (selectedTab) {
                    0 -> HomeScreen(vm, Modifier, onRequestVpnPermission)
                    1 -> ProxiesScreen(vm, Modifier)
                    2 -> ProfilesScreen(vm, Modifier)
                    3 -> LogsScreen(vm, Modifier)
                    4 -> SettingsScreen(vm, Modifier)
                }
            }

            // Bottom nav
            GlassBottomNav(
                screens = screens,
                selectedTab = selectedTab,
                onTabSelected = { selectedTab = it },
                accent = accent,
                isDark = isDark,
            )
        }
    }
}

// ── Glass Top Bar ─────────────────────────────────────────────────────────

@Composable
private fun GlassTopBar(vm: ZephyrViewModel, accent: AppAccent.AccentTheme, isDark: Boolean) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = AppSpacing.Space5, vertical = AppSpacing.Space3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "Zephyr",
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
        )
        if (vm.isCoreRunning) {
            Spacer(modifier = Modifier.width(AppSpacing.Space3))
            // Running status indicator dot with glow
            val infiniteTransition = rememberInfiniteTransition(label = "pulse")
            val pulseAlpha by infiniteTransition.animateFloat(
                initialValue = 0.6f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(
                    animation = tween(1500, easing = AppEasing.EasingSmooth),
                    repeatMode = RepeatMode.Reverse,
                ),
                label = "pulseAlpha",
            )
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(AppColors.ColorEmerald500.copy(alpha = pulseAlpha))
                    .shadow(
                        elevation = 4.dp,
                        shape = CircleShape,
                        ambientColor = AppColors.ColorEmerald500.copy(alpha = 0.5f),
                        spotColor = AppColors.ColorEmerald500.copy(alpha = 0.5f),
                    ),
            )
        }
    }
}

// ── Glass Bottom Navigation Bar ───────────────────────────────────────────

@Composable
private fun GlassBottomNav(
    screens: List<ZephyrScreen>,
    selectedTab: Int,
    onTabSelected: (Int) -> Unit,
    accent: AppAccent.AccentTheme,
    isDark: Boolean,
) {
    val bgColor = Color(0x8C0C0C10) // rgba(12,12,16,0.55)
    val borderColor = Color(0x0DFFFFFF) // rgba(255,255,255,0.05)

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .drawBehind {
                drawLine(
                    color = borderColor,
                    start = Offset(0f, 0f),
                    end = Offset(size.width, 0f),
                    strokeWidth = 1.dp.toPx(),
                )
            }
            .background(bgColor)
            .padding(vertical = AppSpacing.Space2),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = AppSpacing.Space2),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            screens.forEachIndexed { index, screen ->
                val isSelected = selectedTab == index
                val iconColor = when {
                    isSelected -> accent.primary
                    isDark -> AppColors.ColorZinc500
                    else -> AppColors.ColorZinc400
                }
                val labelColor = when {
                    isSelected -> accent.primary
                    isDark -> AppColors.ColorZinc500
                    else -> AppColors.ColorZinc400
                }

                Column(
                    modifier = Modifier
                        .clip(RoundedCornerShape(AppRadius.RadiusMd))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onClick = { onTabSelected(index) },
                        )
                        .padding(horizontal = AppSpacing.Space4, vertical = AppSpacing.Space2),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Icon(
                        screen.icon,
                        contentDescription = screen.label,
                        modifier = Modifier.size(24.dp),
                        tint = iconColor,
                    )
                    Text(
                        screen.label,
                        fontSize = 11.sp,
                        color = labelColor,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

// ── GlassCard composable ─────────────────────────────────────────────────

@Composable
fun GlassCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    selected: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    val isDark = isSystemInDarkTheme()
    val accent = LocalAccentTheme.current

    val bgColor = when {
        selected -> Color.White.copy(alpha = 0.15f)
        isDark -> AppColors.BgSubtle
        else -> AppColors.BgSubtleLight
    }
    val borderColor = when {
        selected -> accent.primary.copy(alpha = 0.4f)
        isDark -> AppColors.BorderPrimary
        else -> AppColors.BorderPrimaryLight
    }
    val shadowElevation = when {
        selected -> 8.dp
        else -> 2.dp
    }

    val shape = RoundedCornerShape(AppCard.radius)

    val clickModifier = if (onClick != null) {
        Modifier.clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null,
            onClick = onClick,
        )
    } else Modifier

    Box(
        modifier = modifier
            .then(clickModifier)
            .shadow(shadowElevation, shape, ambientColor = if (selected) accent.primary.copy(alpha = 0.2f) else Color.Black.copy(alpha = 0.2f), spotColor = if (selected) accent.primary.copy(alpha = 0.2f) else Color.Black.copy(alpha = 0.2f))
            .clip(shape)
            .background(bgColor)
            .then(
                if (selected) {
                    Modifier.drawBehind {
                        drawRoundRect(
                            color = borderColor,
                            style = Stroke(width = 1.dp.toPx()),
                        )
                    }
                } else {
                    Modifier.drawBehind {
                        drawRoundRect(
                            color = borderColor,
                            style = Stroke(width = 1.dp.toPx()),
                        )
                    }
                }
            ),
    ) {
        Column(
            modifier = Modifier.padding(AppSpacing.Space5),
            content = content,
        )
    }
}

// ── IosSwitch composable ─────────────────────────────────────────────────

@Composable
fun IosSwitch(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val accent = LocalAccentTheme.current
    val bgColor by animateColorAsState(
        targetValue = if (checked) accent.primary else Color(0xFF8E8E93),
        animationSpec = tween(AppTime.TimeFast),
        label = "switchBg",
    )
    val thumbOffset by animateDpAsState(
        targetValue = if (checked) (AppSwitch.width - AppSwitch.height) else 0.dp,
        animationSpec = tween(AppTime.TimeFast),
        label = "switchThumb",
    )

    Box(
        modifier = modifier
            .width(AppSwitch.width)
            .height(AppSwitch.height)
            .clip(RoundedCornerShape(AppSwitch.radius))
            .background(bgColor)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onCheckedChange(!checked) },
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(
            modifier = Modifier
                .padding(2.dp)
                .offset(x = thumbOffset)
                .size(AppSwitch.height - 4.dp)
                .clip(CircleShape)
                .background(Color.White)
                .shadow(2.dp, CircleShape),
        )
    }
}

// ── GlowLayer composable ─────────────────────────────────────────────────

@Composable
fun GlowLayer(
    color: Color,
    width: Dp,
    height: Dp,
    blurRadius: Dp = 120.dp,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .width(width)
            .height(height)
            .blur(blurRadius)
            .background(
                Brush.radialGradient(
                    colors = listOf(color, Color.Transparent),
                    radius = 300f,
                ),
            ),
    )
}

// ── Custom Button composables ────────────────────────────────────────────

@Composable
fun BtnGhost(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: @Composable (() -> Unit)? = null,
    active: Boolean = false,
    enabled: Boolean = true,
) {
    val accent = LocalAccentTheme.current
    val isDark = isSystemInDarkTheme()

    val bgColor = when {
        active -> accent.primary.copy(alpha = 0.12f)
        else -> accent.primary.copy(alpha = 0.08f)
    }
    val borderColor = when {
        active -> accent.primary.copy(alpha = 0.25f)
        else -> accent.primary.copy(alpha = 0.12f)
    }
    val textColor = when {
        !enabled -> (if (isDark) AppColors.TextTertiary else AppColors.TextTertiaryLight)
        active -> accent.primary
        else -> if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight
    }

    Row(
        modifier = modifier
            .clip(RoundedCornerShape(AppButton.radius))
            .background(bgColor)
            .drawBehind {
                drawRoundRect(
                    color = borderColor,
                    style = Stroke(width = 1.dp.toPx()),
                )
            }
            .then(
                if (enabled) Modifier.clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onClick,
                ) else Modifier
            )
            .padding(horizontal = AppButton.paddingX, vertical = AppButton.paddingY),
        horizontalArrangement = Arrangement.spacedBy(AppButton.gap),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.invoke()
        Text(
            text.uppercase(),
            fontSize = AppButton.fontSize,
            fontWeight = AppButton.weight,
            letterSpacing = AppButton.tracking,
            color = textColor,
        )
    }
}

@Composable
fun BtnAccent(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: @Composable (() -> Unit)? = null,
    enabled: Boolean = true,
) {
    val accent = LocalAccentTheme.current

    val bgColor = accent.primary.copy(alpha = if (enabled) 0.15f else 0.08f)
    val borderColor = accent.primary.copy(alpha = if (enabled) 0.25f else 0.12f)
    val textColor = accent.primary.copy(alpha = if (enabled) 1f else 0.5f)

    Row(
        modifier = modifier
            .clip(RoundedCornerShape(AppButton.radius))
            .background(bgColor)
            .drawBehind {
                drawRoundRect(
                    color = borderColor,
                    style = Stroke(width = 1.dp.toPx()),
                )
            }
            .then(
                if (enabled) Modifier.clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onClick,
                ) else Modifier
            )
            .padding(horizontal = AppButton.paddingX, vertical = AppButton.paddingY),
        horizontalArrangement = Arrangement.spacedBy(AppButton.gap),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.invoke()
        Text(
            text.uppercase(),
            fontSize = AppButton.fontSize,
            fontWeight = AppButton.weight,
            letterSpacing = AppButton.tracking,
            color = textColor,
        )
    }
}

@Composable
fun BtnPrimary(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: @Composable (() -> Unit)? = null,
    enabled: Boolean = true,
) {
    val accent = LocalAccentTheme.current

    val bgColor = if (enabled) accent.primary else accent.primary.copy(alpha = 0.4f)
    val shadowColor = accent.primary.copy(alpha = if (enabled) 0.3f else 0.1f)

    Row(
        modifier = modifier
            .shadow(
                elevation = 8.dp,
                shape = RoundedCornerShape(AppButton.radius),
                ambientColor = shadowColor,
                spotColor = shadowColor,
            )
            .clip(RoundedCornerShape(AppButton.radius))
            .background(bgColor)
            .then(
                if (enabled) Modifier.clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onClick,
                ) else Modifier
            )
            .padding(horizontal = AppButton.paddingX, vertical = AppButton.paddingY),
        horizontalArrangement = Arrangement.spacedBy(AppButton.gap),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.invoke()
        Text(
            text.uppercase(),
            fontSize = AppButton.fontSize,
            fontWeight = AppButton.weight,
            letterSpacing = AppButton.tracking,
            color = AppColors.TextOnAccent,
        )
    }
}

@Composable
fun BtnDanger(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: @Composable (() -> Unit)? = null,
) {
    val bgColor = AppColors.ColorDanger.copy(alpha = 0.1f)
    val borderColor = AppColors.ColorDanger.copy(alpha = 0.2f)

    Row(
        modifier = modifier
            .clip(RoundedCornerShape(AppButton.radius))
            .background(bgColor)
            .drawBehind {
                drawRoundRect(
                    color = borderColor,
                    style = Stroke(width = 1.dp.toPx()),
                )
            }
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick,
            )
            .padding(horizontal = AppButton.paddingX, vertical = AppButton.paddingY),
        horizontalArrangement = Arrangement.spacedBy(AppButton.gap),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.invoke()
        Text(
            text.uppercase(),
            fontSize = AppButton.fontSize,
            fontWeight = AppButton.weight,
            letterSpacing = AppButton.tracking,
            color = AppColors.ColorDanger,
        )
    }
}

// ── Glass Dialog ─────────────────────────────────────────────────────────

@Composable
fun GlassDialog(
    onDismissRequest: () -> Unit,
    title: String,
    content: @Composable ColumnScope.() -> Unit,
) {
    val accent = LocalAccentTheme.current
    val isDark = isSystemInDarkTheme()

    Dialog(
        onDismissRequest = onDismissRequest,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        // Backdrop blur overlay
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = AppSpacing.Space6),
        ) {
            GlassCard(
                modifier = Modifier.fillMaxWidth(),
            ) {
                // Title
                Text(
                    title,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                )
                Spacer(modifier = Modifier.height(AppSpacing.Space4))
                content()
            }
        }
    }
}

// ── Speed display ────────────────────────────────────────────────────────

@Composable
fun SpeedDisplay(
    uploadSpeed: String,
    downloadSpeed: String,
    modifier: Modifier = Modifier,
) {
    val isDark = isSystemInDarkTheme()
    val accent = LocalAccentTheme.current
    val textColor = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight
    val unitColor = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight
    val dividerColor = if (isDark) AppColors.BorderPrimary else AppColors.BorderPrimaryLight

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Download
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                downloadSpeed,
                fontSize = 64.sp,
                fontWeight = FontWeight.ExtraLight,
                color = textColor,
                style = androidx.compose.ui.text.TextStyle(
                    fontFeatureSettings = "tnum",
                ),
            )
            Text(
                "DOWNLOAD",
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = unitColor,
                letterSpacing = 0.1.sp,
            )
        }

        // Vertical divider with gradient
        Box(
            modifier = Modifier
                .width(1.dp)
                .height(64.dp)
                .padding(horizontal = AppSpacing.Space5)
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color.Transparent,
                            dividerColor,
                            Color.Transparent,
                        ),
                    ),
                ),
        )

        // Upload
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                uploadSpeed,
                fontSize = 64.sp,
                fontWeight = FontWeight.ExtraLight,
                color = textColor,
                style = androidx.compose.ui.text.TextStyle(
                    fontFeatureSettings = "tnum",
                ),
            )
            Text(
                "UPLOAD",
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = unitColor,
                letterSpacing = 0.1.sp,
            )
        }
    }
}

// ── Home screen ──────────────────────────────────────────────────────────

@Composable
fun HomeScreen(vm: ZephyrViewModel, modifier: Modifier = Modifier, onRequestVpnPermission: () -> Unit = {}) {
    val accent = LocalAccentTheme.current

    Box(modifier = modifier.fillMaxSize()) {
        // Glow layer
        GlowLayer(
            color = accent.primary.copy(alpha = 0.1f),
            width = 600.dp,
            height = 300.dp,
            modifier = Modifier.align(Alignment.Center),
        )

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = AppSpacing.Space5),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.Space4),
            contentPadding = PaddingValues(vertical = AppSpacing.Space5),
        ) {
            // Core status card
            item {
                CoreStatusCard(vm, onRequestVpnPermission)
            }

            // Proxy mode selector
            item {
                ProxyModeCard(vm)
            }

            // TUN + System proxy toggles
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(AppSpacing.Space3),
                ) {
                    ToggleCard(
                        title = "TUN Mode",
                        subtitle = "Virtual Adapter",
                        checked = vm.tunEnabled,
                        onCheckedChange = { vm.setTunEnabled(it) },
                        modifier = Modifier.weight(1f),
                        iconColor = AppColors.ColorPink500,
                    )
                    ToggleCard(
                        title = "System Proxy",
                        subtitle = "HTTP/SOCKS Proxy",
                        checked = vm.systemProxyEnabled,
                        onCheckedChange = { vm.setSystemProxyEnabled(it) },
                        modifier = Modifier.weight(1f),
                        iconColor = AppColors.ColorBlue500,
                    )
                }
            }

            // Speed display
            if (vm.isCoreRunning) {
                item {
                    SpeedDisplay(
                        uploadSpeed = "0",
                        downloadSpeed = "0",
                    )
                }
            }

            // Current node display
            if (vm.isCoreRunning && vm.currentNodeName.isNotEmpty()) {
                item {
                    CurrentNodeCard(vm)
                }
            }

            // Event log
            item {
                EventLogCard(vm)
            }
        }
    }
}

@Composable
private fun CoreStatusCard(vm: ZephyrViewModel, onRequestVpnPermission: () -> Unit = {}) {
    val accent = LocalAccentTheme.current
    val isDark = isSystemInDarkTheme()

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        selected = vm.isCoreRunning,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (vm.isCoreRunning) "Core Running" else "Core Stopped",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                )
                Spacer(modifier = Modifier.height(AppSpacing.Space1))
                Text(
                    text = if (vm.isCoreRunning) {
                        "Proxy active on port ${vm.mixedPort}"
                    } else {
                        "Tap the switch to start"
                    },
                    fontSize = 13.sp,
                    color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                )
            }
            if (vm.isStartingCore) {
                CircularProgressIndicator(
                    modifier = Modifier.size(32.dp),
                    strokeWidth = 3.dp,
                    color = accent.primary,
                )
            } else {
                IosSwitch(
                    checked = vm.isCoreRunning,
                    onCheckedChange = { enabled ->
                        if (enabled) {
                            if (vm.checkVpnPermission()) {
                                onRequestVpnPermission()
                            } else {
                                vm.toggleCore(true)
                            }
                        } else {
                            vm.toggleCore(false)
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun ProxyModeCard(vm: ZephyrViewModel) {
    val accent = LocalAccentTheme.current
    val isDark = isSystemInDarkTheme()

    GlassCard(modifier = Modifier.fillMaxWidth()) {
        Text(
            "Proxy Mode",
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
        )
        Spacer(modifier = Modifier.height(AppSpacing.Space3))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(AppSpacing.Space2),
        ) {
            listOf("Rule" to "rule", "Global" to "global", "Direct" to "direct").forEach { (label, mode) ->
                val isActive = vm.proxyMode.equals(mode, ignoreCase = true)
                BtnGhost(
                    text = label,
                    onClick = { vm.setProxyMode(mode) },
                    active = isActive,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun ToggleCard(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    iconColor: Color = MaterialTheme.colorScheme.primary,
) {
    val isDark = isSystemInDarkTheme()

    GlassCard(modifier = modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    title,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                )
                Text(
                    subtitle,
                    fontSize = 11.sp,
                    color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                )
            }
            IosSwitch(checked = checked, onCheckedChange = onCheckedChange)
        }
    }
}

@Composable
private fun CurrentNodeCard(vm: ZephyrViewModel) {
    val accent = LocalAccentTheme.current
    val isDark = isSystemInDarkTheme()

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        selected = true,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Selected indicator dot with pulse
            val infiniteTransition = rememberInfiniteTransition(label = "nodePulse")
            val pulseAlpha by infiniteTransition.animateFloat(
                initialValue = 0.7f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(
                    animation = tween(1200, easing = AppEasing.EasingSmooth),
                    repeatMode = RepeatMode.Reverse,
                ),
                label = "nodePulseAlpha",
            )
            Box(
                modifier = Modifier
                    .size(2.5.dp)
                    .clip(CircleShape)
                    .background(accent.primary.copy(alpha = pulseAlpha))
                    .shadow(
                        elevation = 4.dp,
                        shape = CircleShape,
                        ambientColor = accent.primary.copy(alpha = 0.4f),
                        spotColor = accent.primary.copy(alpha = 0.4f),
                    ),
            )
            Spacer(modifier = Modifier.width(AppSpacing.Space3))
            Column {
                Text(
                    "Current Node",
                    fontSize = 11.sp,
                    color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                )
                Text(
                    vm.currentNodeName,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun EventLogCard(vm: ZephyrViewModel) {
    val isDark = isSystemInDarkTheme()

    GlassCard(modifier = Modifier.fillMaxWidth()) {
        Text(
            "Event Log",
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
        )
        Spacer(modifier = Modifier.height(AppSpacing.Space3))
        if (vm.events.isEmpty()) {
            Text(
                "No events yet",
                fontSize = 12.sp,
                color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
            )
        } else {
            vm.events.takeLast(8).forEach { event ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 2.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    Text(
                        "[${event.level}]",
                        fontSize = 10.sp,
                        fontFamily = FontFamily.Monospace,
                        color = when (event.level) {
                            "Error", "Fatal" -> AppColors.ColorRed500
                            "Warn" -> AppColors.ColorAmber500
                            else -> if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight
                        },
                        modifier = Modifier.width(48.dp),
                    )
                    Text(
                        event.message,
                        fontSize = 12.sp,
                        color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

// ── Proxies screen ───────────────────────────────────────────────────────

@Composable
fun ProxiesScreen(vm: ZephyrViewModel, modifier: Modifier = Modifier) {
    val accent = LocalAccentTheme.current
    val isDark = isSystemInDarkTheme()

    Box(modifier = modifier.fillMaxSize()) {
        // Glow layer - top right
        GlowLayer(
            color = accent.primary.copy(alpha = 0.05f),
            width = 500.dp,
            height = 300.dp,
            blurRadius = 100.dp,
            modifier = Modifier.align(Alignment.TopEnd),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = AppSpacing.Space5),
        ) {
            // Header with group selector
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = AppSpacing.Space4),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Proxy Nodes",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                )

                Row(horizontalArrangement = Arrangement.spacedBy(AppSpacing.Space2)) {
                    // Sort button
                    var sortExpanded by remember { mutableStateOf(false) }
                    Box {
                        BtnGhost(
                            text = when (vm.proxySortMode) {
                                "name" -> "Name"
                                "latency" -> "Latency"
                                "smart" -> "Smart"
                                else -> "Default"
                            },
                            onClick = { sortExpanded = true },
                            icon = {
                                Icon(
                                    Icons.Filled.ArrowDropDown,
                                    contentDescription = null,
                                    modifier = Modifier.size(14.dp),
                                    tint = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                                )
                            },
                        )
                        DropdownMenu(
                            expanded = sortExpanded,
                            onDismissRequest = { sortExpanded = false },
                        ) {
                            listOf("default" to "Default", "name" to "Name", "latency" to "Latency", "smart" to "Smart").forEach { (mode, label) ->
                                DropdownMenuItem(
                                    text = { Text(label) },
                                    onClick = {
                                        vm.setSortMode(mode)
                                        sortExpanded = false
                                    },
                                )
                            }
                        }
                    }

                    // Smart select best
                    if (vm.smartEnabled) {
                        BtnAccent(
                            text = "Best",
                            onClick = { vm.smartSelectBest() },
                            icon = {
                                Icon(
                                    Icons.Filled.Star,
                                    contentDescription = null,
                                    modifier = Modifier.size(14.dp),
                                    tint = accent.primary,
                                )
                            },
                        )
                    }

                    // Latency test
                    BtnPrimary(
                        text = "Test",
                        onClick = { vm.testLatency() },
                        enabled = !vm.isTestingLatency,
                        icon = {
                            if (vm.isTestingLatency) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(14.dp),
                                    strokeWidth = 2.dp,
                                    color = AppColors.TextOnAccent,
                                )
                            } else {
                                Icon(
                                    Icons.Filled.Speed,
                                    contentDescription = null,
                                    modifier = Modifier.size(14.dp),
                                    tint = AppColors.TextOnAccent,
                                )
                            }
                        },
                    )
                }
            }

            // Group selector dropdown
            if (vm.proxyGroups.isNotEmpty()) {
                var groupExpanded by remember { mutableStateOf(false) }
                Box(modifier = Modifier.padding(bottom = AppSpacing.Space3)) {
                    BtnGhost(
                        text = vm.currentGroupName.ifEmpty { "Select Group" },
                        onClick = { groupExpanded = true },
                        icon = {
                            Icon(
                                Icons.Filled.ArrowDropDown,
                                contentDescription = null,
                                modifier = Modifier.size(14.dp),
                                tint = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                            )
                        },
                    )
                    DropdownMenu(
                        expanded = groupExpanded,
                        onDismissRequest = { groupExpanded = false },
                    ) {
                        vm.proxyGroups.forEach { group ->
                            DropdownMenuItem(
                                text = { Text(group.name) },
                                onClick = {
                                    vm.selectProxyGroup(group.name)
                                    groupExpanded = false
                                },
                            )
                        }
                    }
                }
            }

            // Node cards grid
            val currentGroup = vm.proxyGroups.find { it.name == vm.currentGroupName }
            val nodes = currentGroup?.nodes ?: emptyList()

            if (nodes.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            Icons.Filled.CloudOff,
                            contentDescription = null,
                            modifier = Modifier.size(48.dp),
                            tint = if (isDark) AppColors.ColorZinc500 else AppColors.ColorZinc400,
                        )
                        Spacer(modifier = Modifier.height(AppSpacing.Space3))
                        Text(
                            "No proxy nodes available",
                            fontSize = 15.sp,
                            color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                        )
                        Text(
                            "Start the core and select a profile",
                            fontSize = 12.sp,
                            color = if (isDark) AppColors.TextTertiary else AppColors.TextTertiaryLight,
                        )
                    }
                }
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(AppSpacing.Space3),
                    contentPadding = PaddingValues(vertical = AppSpacing.Space2),
                    modifier = Modifier.weight(1f),
                ) {
                    items(nodes, key = { it.name }) { node ->
                        ProxyNodeCard(
                            node = node,
                            isSelected = node.name == currentGroup?.current,
                            onSelect = { vm.selectProxyNode(vm.currentGroupName, node.name) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ProxyNodeCard(
    node: ProxyNode,
    isSelected: Boolean,
    onSelect: () -> Unit,
) {
    val accent = LocalAccentTheme.current
    val isDark = isSystemInDarkTheme()

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onSelect,
        selected = isSelected,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    // Selected indicator dot with pulse
                    if (isSelected) {
                        val infiniteTransition = rememberInfiniteTransition(label = "proxyPulse")
                        val pulseAlpha by infiniteTransition.animateFloat(
                            initialValue = 0.7f,
                            targetValue = 1f,
                            animationSpec = infiniteRepeatable(
                                animation = tween(1200, easing = AppEasing.EasingSmooth),
                                repeatMode = RepeatMode.Reverse,
                            ),
                            label = "proxyPulseAlpha",
                        )
                        Box(
                            modifier = Modifier
                                .size(2.5.dp)
                                .clip(CircleShape)
                                .background(accent.primary.copy(alpha = pulseAlpha))
                                .shadow(
                                    elevation = 4.dp,
                                    shape = CircleShape,
                                    ambientColor = accent.primary.copy(alpha = 0.4f),
                                    spotColor = accent.primary.copy(alpha = 0.4f),
                                ),
                        )
                        Spacer(modifier = Modifier.width(AppSpacing.Space2))
                    }
                    Text(
                        node.name,
                        fontSize = 14.sp,
                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                        color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (node.type.isNotEmpty()) {
                    Text(
                        node.type,
                        fontSize = 10.sp,
                        color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                    )
                }
            }

            // Latency badge
            LatencyBadge(latency = node.latency, alive = node.alive)
        }
    }
}

@Composable
private fun LatencyBadge(latency: Int, alive: Boolean) {
    val (text, color) = when {
        latency <= 0 -> "Timeout" to AppColors.ColorRed500
        latency < 200 -> "${latency}ms" to AppColors.ColorEmerald500
        latency < 500 -> "${latency}ms" to AppColors.ColorAmber500
        else -> "${latency}ms" to AppColors.ColorRed500
    }
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(AppBadge.radius))
            .background(color.copy(alpha = 0.15f))
            .padding(horizontal = 8.dp, vertical = 3.dp),
    ) {
        Text(
            text,
            fontSize = AppBadge.fontSize,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            color = color,
        )
    }
}

// ── Profiles screen ──────────────────────────────────────────────────────

@Composable
fun ProfilesScreen(vm: ZephyrViewModel, modifier: Modifier = Modifier) {
    val accent = LocalAccentTheme.current
    val isDark = isSystemInDarkTheme()

    Box(modifier = modifier.fillMaxSize()) {
        // Glow layer
        GlowLayer(
            color = accent.primary.copy(alpha = 0.05f),
            width = 400.dp,
            height = 250.dp,
            modifier = Modifier.align(Alignment.BottomCenter),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = AppSpacing.Space5),
        ) {
            // Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = AppSpacing.Space4),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Subscriptions",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(AppSpacing.Space2)) {
                    if (vm.profiles.isNotEmpty()) {
                        BtnGhost(
                            text = "Update All",
                            onClick = { vm.updateAllProfiles() },
                            enabled = !vm.isUpdatingSubscriptions,
                            icon = {
                                Icon(
                                    Icons.Filled.Refresh,
                                    contentDescription = null,
                                    modifier = Modifier.size(14.dp),
                                    tint = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                                )
                            },
                        )
                    }
                    BtnPrimary(
                        text = "Add",
                        onClick = { vm.showAddProfileDialog = true },
                        icon = {
                            Icon(
                                Icons.Filled.Add,
                                contentDescription = null,
                                modifier = Modifier.size(14.dp),
                                tint = AppColors.TextOnAccent,
                            )
                        },
                    )
                }
            }

            // Profile list
            if (vm.profiles.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            Icons.Filled.CloudDownload,
                            contentDescription = null,
                            modifier = Modifier.size(48.dp),
                            tint = if (isDark) AppColors.ColorZinc500 else AppColors.ColorZinc400,
                        )
                        Spacer(modifier = Modifier.height(AppSpacing.Space3))
                        Text(
                            "No profiles yet",
                            fontSize = 15.sp,
                            color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                        )
                        Text(
                            "Add a subscription URL to get started",
                            fontSize = 12.sp,
                            color = if (isDark) AppColors.TextTertiary else AppColors.TextTertiaryLight,
                        )
                    }
                }
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(AppSpacing.Space3),
                    contentPadding = PaddingValues(vertical = AppSpacing.Space2),
                    modifier = Modifier.weight(1f),
                ) {
                    items(vm.profiles, key = { it.name }) { profile ->
                        ProfileCard(
                            profile = profile,
                            isActive = profile.name == vm.activeProfile,
                            onSelect = { vm.setActiveProfile(profile.name) },
                            onUpdate = { vm.updateProfile(profile.name) },
                            onDelete = { vm.deleteProfile(profile.name) },
                            onRename = { newName -> vm.renameProfile(profile.name, newName) },
                        )
                    }
                }
            }
        }
    }

    // Add profile dialog
    if (vm.showAddProfileDialog) {
        AddProfileDialog(vm)
    }
}

@Composable
private fun ProfileCard(
    profile: ProfileItem,
    isActive: Boolean,
    onSelect: () -> Unit,
    onUpdate: () -> Unit,
    onDelete: () -> Unit,
    onRename: (String) -> Unit,
) {
    val accent = LocalAccentTheme.current
    val isDark = isSystemInDarkTheme()
    var showActions by remember { mutableStateOf(false) }
    var showRenameDialog by remember { mutableStateOf(false) }
    var renameText by remember { mutableStateOf("") }

    GlassCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onSelect,
        selected = isActive,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (isActive) {
                        // Active indicator dot with pulse
                        val infiniteTransition = rememberInfiniteTransition(label = "profilePulse")
                        val pulseAlpha by infiniteTransition.animateFloat(
                            initialValue = 0.7f,
                            targetValue = 1f,
                            animationSpec = infiniteRepeatable(
                                animation = tween(1200, easing = AppEasing.EasingSmooth),
                                repeatMode = RepeatMode.Reverse,
                            ),
                            label = "profilePulseAlpha",
                        )
                        Box(
                            modifier = Modifier
                                .size(2.5.dp)
                                .clip(CircleShape)
                                .background(accent.primary.copy(alpha = pulseAlpha))
                                .shadow(
                                    elevation = 4.dp,
                                    shape = CircleShape,
                                    ambientColor = accent.primary.copy(alpha = 0.4f),
                                    spotColor = accent.primary.copy(alpha = 0.4f),
                                ),
                        )
                        Spacer(modifier = Modifier.width(AppSpacing.Space2))
                    }
                    Text(
                        profile.name,
                        fontSize = 13.sp,
                        fontWeight = if (isActive) FontWeight.Bold else FontWeight.Normal,
                        color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                    )
                }
                profile.urlDisplay?.let { url ->
                    Text(
                        url,
                        fontSize = 11.sp,
                        color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(start = if (isActive) 16.dp else 0.dp),
                    )
                }
                profile.subInfo?.let { info ->
                    Text(
                        info,
                        fontSize = 10.sp,
                        color = if (isDark) AppColors.TextTertiary else AppColors.TextTertiaryLight,
                        modifier = Modifier.padding(start = if (isActive) 16.dp else 0.dp),
                    )
                }
            }

            // Action buttons
            Row {
                IconButton(onClick = onUpdate, modifier = Modifier.size(32.dp)) {
                    Icon(
                        Icons.Filled.Refresh,
                        contentDescription = "Update",
                        modifier = Modifier.size(16.dp),
                        tint = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                    )
                }
                IconButton(onClick = { showActions = true }, modifier = Modifier.size(32.dp)) {
                    Icon(
                        Icons.Filled.MoreVert,
                        contentDescription = "More",
                        modifier = Modifier.size(16.dp),
                        tint = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                    )
                }
                DropdownMenu(expanded = showActions, onDismissRequest = { showActions = false }) {
                    DropdownMenuItem(
                        text = { Text("Rename") },
                        onClick = {
                            renameText = profile.name
                            showRenameDialog = true
                            showActions = false
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Filled.Edit,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                            )
                        },
                    )
                    DropdownMenuItem(
                        text = { Text("Delete", color = AppColors.ColorRed500) },
                        onClick = {
                            onDelete()
                            showActions = false
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Filled.Delete,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = AppColors.ColorRed500,
                            )
                        },
                    )
                }
            }
        }
    }

    // Rename dialog
    if (showRenameDialog) {
        GlassDialog(
            onDismissRequest = { showRenameDialog = false },
            title = "Rename Profile",
        ) {
            OutlinedTextField(
                value = renameText,
                onValueChange = { renameText = it },
                singleLine = true,
                label = { Text("Name") },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AppInput.radius),
            )
            Spacer(modifier = Modifier.height(AppSpacing.Space4))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                BtnGhost(
                    text = "Cancel",
                    onClick = { showRenameDialog = false },
                )
                Spacer(modifier = Modifier.width(AppSpacing.Space3))
                BtnPrimary(
                    text = "Confirm",
                    onClick = {
                        if (renameText.isNotBlank()) {
                            onRename(renameText)
                        }
                        showRenameDialog = false
                    },
                    enabled = renameText.isNotBlank(),
                )
            }
        }
    }
}

@Composable
private fun AddProfileDialog(vm: ZephyrViewModel) {
    val isDark = isSystemInDarkTheme()

    GlassDialog(
        onDismissRequest = {
            vm.showAddProfileDialog = false
            vm.addProfileUrl = ""
            vm.addProfileName = ""
        },
        title = "Add Subscription",
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.Space3)) {
            OutlinedTextField(
                value = vm.addProfileUrl,
                onValueChange = { vm.addProfileUrl = it },
                label = { Text("Subscription URL") },
                singleLine = true,
                placeholder = { Text("https://...") },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AppInput.radius),
            )
            OutlinedTextField(
                value = vm.addProfileName,
                onValueChange = { vm.addProfileName = it },
                label = { Text("Profile Name (optional)") },
                singleLine = true,
                placeholder = { Text("Auto-detect from URL") },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AppInput.radius),
            )
        }
        Spacer(modifier = Modifier.height(AppSpacing.Space4))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BtnGhost(
                text = "Cancel",
                onClick = {
                    vm.showAddProfileDialog = false
                    vm.addProfileUrl = ""
                    vm.addProfileName = ""
                },
            )
            Spacer(modifier = Modifier.width(AppSpacing.Space3))
            BtnPrimary(
                text = "Add",
                onClick = {
                    if (vm.addProfileUrl.isNotBlank()) {
                        vm.addProfile(vm.addProfileUrl, vm.addProfileName)
                        vm.addProfileUrl = ""
                        vm.addProfileName = ""
                        vm.showAddProfileDialog = false
                    }
                },
                enabled = vm.addProfileUrl.isNotBlank(),
            )
        }
    }
}

// ── Logs screen ──────────────────────────────────────────────────────────

@Composable
fun LogsScreen(vm: ZephyrViewModel, modifier: Modifier = Modifier) {
    val accent = LocalAccentTheme.current
    val isDark = isSystemInDarkTheme()

    Box(modifier = modifier.fillMaxSize()) {
        // Glow layer
        GlowLayer(
            color = accent.primary.copy(alpha = 0.03f),
            width = 400.dp,
            height = 200.dp,
            modifier = Modifier.align(Alignment.BottomStart),
        )

        Column(modifier = Modifier.fillMaxSize()) {
            // Header with filter
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = AppSpacing.Space5, vertical = AppSpacing.Space4),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Logs",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(AppSpacing.Space2),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Level filter buttons
                    listOf("all", "info", "warn", "error").forEach { level ->
                        BtnGhost(
                            text = level.replaceFirstChar { it.uppercase() },
                            onClick = { vm.setLogLevelFilter(level) },
                            active = vm.logLevelFilter.equals(level, ignoreCase = true),
                        )
                    }
                    // Clear button
                    IconButton(onClick = { vm.clearLogs() }) {
                        Icon(
                            Icons.Filled.DeleteSweep,
                            contentDescription = "Clear Logs",
                            tint = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                        )
                    }
                }
            }

            // Log content
            val filteredLogs = vm.filteredLogs
            val listState = rememberLazyListState()

            // Auto-scroll to bottom
            LaunchedEffect(filteredLogs.size) {
                if (filteredLogs.isNotEmpty()) {
                    listState.animateScrollToItem(filteredLogs.size - 1)
                }
            }

            if (filteredLogs.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            Icons.Filled.Terminal,
                            contentDescription = null,
                            modifier = Modifier.size(48.dp),
                            tint = if (isDark) AppColors.ColorZinc500 else AppColors.ColorZinc400,
                        )
                        Spacer(modifier = Modifier.height(AppSpacing.Space3))
                        Text(
                            "No logs yet",
                            fontSize = 15.sp,
                            color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                        )
                    }
                }
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .padding(horizontal = AppSpacing.Space5),
                    verticalArrangement = Arrangement.spacedBy(1.dp),
                ) {
                    items(filteredLogs, key = { "${it.timestamp}-${it.message}" }) { log ->
                        LogEntryRow(log)
                    }
                }
            }
        }
    }
}

@Composable
private fun LogEntryRow(entry: LogEntry) {
    val isDark = isSystemInDarkTheme()
    val levelColor = when (entry.level) {
        "Error", "Fatal" -> AppColors.ColorRed500
        "Warn" -> AppColors.ColorAmber500
        "Info" -> AppColors.ColorBlue500
        else -> if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
    ) {
        Text(
            "[${entry.level.uppercase()}]",
            fontSize = 10.sp,
            fontFamily = FontFamily.Monospace,
            color = levelColor,
            modifier = Modifier.width(52.dp),
        )
        Text(
            entry.message,
            fontSize = 12.sp,
            fontFamily = FontFamily.Monospace,
            color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
        )
    }
}

// ── Settings screen ──────────────────────────────────────────────────────

@Composable
fun SettingsScreen(vm: ZephyrViewModel, modifier: Modifier = Modifier) {
    val accent = LocalAccentTheme.current
    val isDark = isSystemInDarkTheme()

    Box(modifier = modifier.fillMaxSize()) {
        // Glow layer
        GlowLayer(
            color = accent.primary.copy(alpha = 0.03f),
            width = 400.dp,
            height = 200.dp,
            modifier = Modifier.align(Alignment.CenterEnd),
        )

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = AppSpacing.Space5),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.Space5),
            contentPadding = PaddingValues(vertical = AppSpacing.Space5),
        ) {
            // General
            item {
                SettingsSectionHeader("General")
                GlassCard(modifier = Modifier.fillMaxWidth()) {
                    // Theme mode
                    SettingsRow(
                        title = "Theme",
                        subtitle = "Auto / Light / Dark",
                    ) {
                        Row(horizontalArrangement = Arrangement.spacedBy(AppSpacing.Space1)) {
                            listOf("light" to "Light", "auto" to "Auto", "dark" to "Dark").forEach { (mode, label) ->
                                BtnGhost(
                                    text = label,
                                    onClick = { vm.themeMode = mode },
                                    active = vm.themeMode == mode,
                                )
                            }
                        }
                    }

                    GlassDivider()

                    // Language
                    SettingsRow(
                        title = "Language",
                        subtitle = "Interface language",
                    ) {
                        Row(horizontalArrangement = Arrangement.spacedBy(AppSpacing.Space1)) {
                            listOf("zh" to "中文", "en" to "English").forEach { (code, label) ->
                                BtnGhost(
                                    text = label,
                                    onClick = { vm.language = code },
                                    active = vm.language == code,
                                )
                            }
                        }
                    }
                }
            }

            // Network
            item {
                SettingsSectionHeader("Network & Routing")
                GlassCard(modifier = Modifier.fillMaxWidth()) {
                    SettingsToggleRow("IPv6 Support", "Enable IPv6 routing and connections", vm.ipv6Enabled) { vm.setIpv6Enabled(it) }
                    GlassDivider()
                    SettingsToggleRow("Allow LAN", "Allow local network devices to connect", vm.allowLan) { vm.setAllowLan(it) }
                    GlassDivider()
                    SettingsToggleRow("Unified Delay", "Use uniform delay testing strategy", vm.unifiedDelay) { vm.setUnifiedDelay(it) }
                    GlassDivider()

                    // Port settings
                    var showPortDialog by remember { mutableStateOf(false) }
                    SettingsRow(
                        title = "Port Settings",
                        subtitle = "Mixed: ${vm.mixedPort}  SOCKS: ${vm.socksPort}",
                    ) {
                        BtnGhost(
                            text = "Configure",
                            onClick = { showPortDialog = true },
                        )
                    }

                    if (showPortDialog) {
                        PortConfigDialog(vm, onDismiss = { showPortDialog = false })
                    }
                }
            }

            // Core
            item {
                SettingsSectionHeader("Mihomo Core")
                GlassCard(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column {
                            Text(
                                "Current Version",
                                fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                            )
                            Text(
                                "Core: ${vm.coreVersion.ifEmpty { "unknown" }}",
                                fontSize = 12.sp,
                                color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                            )
                        }
                        BtnGhost(
                            text = "Check Update",
                            onClick = { vm.refreshCoreVersion() },
                        )
                    }
                }
            }

            // Smart Selector
            item {
                SettingsSectionHeader("Smart Proxy Selector")
                GlassCard(modifier = Modifier.fillMaxWidth()) {
                    SettingsToggleRow(
                        "Smart Proxy Selector",
                        "Auto-select best proxy using EMA scoring",
                        vm.smartEnabled,
                    ) { vm.setSmartEnabled(it) }
                    GlassDivider()
                    SettingsToggleRow(
                        "Auto Speed Test",
                        "Periodically test all proxies to keep scores accurate",
                        vm.smartAutoTest,
                    ) { vm.setSmartAutoTest(it) }

                    if (vm.smartEnabled) {
                        GlassDivider()
                        Text(
                            "Scoring Weights",
                            fontSize = 11.sp,
                            color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                        )
                        Spacer(modifier = Modifier.height(AppSpacing.Space2))
                        WeightSlider("Latency", vm.smartLatencyWeight.toFloat()) { vm.smartLatencyWeight = it.toDouble() }
                        WeightSlider("Success Rate", vm.smartSuccessWeight.toFloat()) { vm.smartSuccessWeight = it.toDouble() }
                        WeightSlider("Stability", vm.smartStabilityWeight.toFloat()) { vm.smartStabilityWeight = it.toDouble() }
                    }
                }
            }

            // Failover
            item {
                SettingsSectionHeader("Failover")
                GlassCard(modifier = Modifier.fillMaxWidth()) {
                    SettingsToggleRow(
                        "Failover",
                        "Auto-switch when current node fails consecutively",
                        vm.failoverEnabled,
                    ) { vm.setFailoverEnabled(it) }

                    if (vm.failoverEnabled) {
                        GlassDivider()
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column {
                                Text(
                                    "Failure Threshold",
                                    fontSize = 13.sp,
                                    color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                                )
                                Text(
                                    "Consecutive failures before switching",
                                    fontSize = 11.sp,
                                    color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                                )
                            }
                            Text(
                                "${vm.failoverThreshold}",
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = FontFamily.Monospace,
                                color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                            )
                        }
                        Slider(
                            value = vm.failoverThreshold.toFloat(),
                            onValueChange = { vm.setFailoverThreshold(it.toUInt()) },
                            valueRange = 1f..10f,
                            steps = 8,
                        )

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column {
                                Text(
                                    "Cooldown",
                                    fontSize = 13.sp,
                                    color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                                )
                                Text(
                                    "Seconds before retrying failed node",
                                    fontSize = 11.sp,
                                    color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
                                )
                            }
                            Text(
                                "${vm.failoverCooldownSecs}s",
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = FontFamily.Monospace,
                                color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
                            )
                        }
                        Slider(
                            value = vm.failoverCooldownSecs.toFloat(),
                            onValueChange = { vm.setFailoverCooldown(it.toULong()) },
                            valueRange = 10f..300f,
                        )

                        GlassDivider()
                        OutlinedTextField(
                            value = vm.failoverFallbackGroup,
                            onValueChange = { vm.setFailoverFallbackGroup(it) },
                            label = { Text("Fallback Group") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(AppInput.radius),
                        )
                    }
                }
            }

            // Bottom spacer
            item {
                Spacer(modifier = Modifier.height(AppSpacing.Space8))
            }
        }
    }
}

@Composable
private fun GlassDivider() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = AppSpacing.Space3)
            .height(1.dp)
            .background(AppColors.BorderSubtle),
    )
}

@Composable
private fun SettingsSectionHeader(title: String) {
    val isDark = isSystemInDarkTheme()
    Text(
        title,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
        modifier = Modifier.padding(start = AppSpacing.Space1, bottom = AppSpacing.Space2),
    )
}

@Composable
private fun SettingsRow(
    title: String,
    subtitle: String,
    action: @Composable () -> Unit,
) {
    val isDark = isSystemInDarkTheme()
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                title,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
            )
            Text(
                subtitle,
                fontSize = 11.sp,
                color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
            )
        }
        action()
    }
}

@Composable
private fun SettingsToggleRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    val isDark = isSystemInDarkTheme()
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                title,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
            )
            Text(
                subtitle,
                fontSize = 11.sp,
                color = if (isDark) AppColors.TextSecondary else AppColors.TextSecondaryLight,
            )
        }
        IosSwitch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun WeightSlider(label: String, value: Float, onValueChange: (Float) -> Unit) {
    val isDark = isSystemInDarkTheme()
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            label,
            fontSize = 12.sp,
            color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
            modifier = Modifier.width(80.dp),
        )
        Slider(
            value = value,
            onValueChange = onValueChange,
            valueRange = 0f..1f,
            modifier = Modifier.weight(1f),
        )
        Text(
            "%.2f".format(value),
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            color = if (isDark) AppColors.TextPrimary else AppColors.TextPrimaryLight,
            modifier = Modifier.width(40.dp),
            textAlign = TextAlign.End,
        )
    }
}

@Composable
private fun PortConfigDialog(vm: ZephyrViewModel, onDismiss: () -> Unit) {
    var mixedPortText by remember { mutableStateOf(vm.mixedPort.toString()) }
    var socksPortText by remember { mutableStateOf(vm.socksPort.toString()) }
    var httpPortText by remember { mutableStateOf(vm.httpPort.toString()) }

    GlassDialog(
        onDismissRequest = onDismiss,
        title = "Port Configuration",
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.Space3)) {
            OutlinedTextField(
                value = mixedPortText,
                onValueChange = { mixedPortText = it },
                label = { Text("Mixed Port") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AppInput.radius),
            )
            OutlinedTextField(
                value = socksPortText,
                onValueChange = { socksPortText = it },
                label = { Text("SOCKS5 Port") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AppInput.radius),
            )
            OutlinedTextField(
                value = httpPortText,
                onValueChange = { httpPortText = it },
                label = { Text("HTTP Port") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AppInput.radius),
            )
        }
        Spacer(modifier = Modifier.height(AppSpacing.Space4))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BtnGhost(
                text = "Cancel",
                onClick = onDismiss,
            )
            Spacer(modifier = Modifier.width(AppSpacing.Space3))
            BtnPrimary(
                text = "Save",
                onClick = {
                    mixedPortText.toUShortOrNull()?.let { vm.updateMixedPort(it) }
                    socksPortText.toUShortOrNull()?.let { vm.updateSocksPort(it) }
                    httpPortText.toUShortOrNull()?.let { vm.updateHttpPort(it) }
                    onDismiss()
                },
            )
        }
    }
}

private fun String.toUShortOrNull(): UShort? {
    return toUShortOrNull()
}
