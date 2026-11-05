package com.zephyr.app

import android.app.Activity
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.zephyr.ui.theme.ZephyrTheme

class MainActivity : ComponentActivity() {

    private lateinit var vm: ZephyrViewModel

    private val vpnPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        vm.onVpnPermissionResult(result.resultCode == Activity.RESULT_OK)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            vm = viewModel()
            // Use themeMode from ViewModel to control dark/light
            val darkTheme = when (vm.themeMode) {
                "light" -> false
                "dark" -> true
                else -> androidx.compose.foundation.isSystemInDarkTheme()
            }
            ZephyrTheme(darkTheme = darkTheme) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    ZephyrApp(
                        vm = vm,
                        onRequestVpnPermission = {
                            val intent = android.net.VpnService.prepare(this)
                            if (intent != null) {
                                vpnPermissionLauncher.launch(intent)
                            } else {
                                vm.onVpnPermissionResult(true)
                            }
                        }
                    )
                }
            }
        }
    }
}
