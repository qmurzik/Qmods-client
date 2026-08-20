package ru.qmods.client.presentation.screens.device

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Android
import androidx.compose.material.icons.rounded.CalendarToday
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.LinkOff
import androidx.compose.material.icons.rounded.Fingerprint
import androidx.compose.material.icons.rounded.PhoneAndroid
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ru.qmods.client.R
import ru.qmods.client.domain.model.Device
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.presentation.components.ConfirmDialog
import ru.qmods.client.presentation.components.EmptyState
import ru.qmods.client.presentation.components.ErrorState
import ru.qmods.client.presentation.components.RefreshableScreen
import ru.qmods.client.presentation.components.SkeletonList
import ru.qmods.client.presentation.components.SolidCard
import ru.qmods.client.presentation.theme.AccentCyan
import ru.qmods.client.presentation.theme.ErrorRed
import ru.qmods.client.presentation.theme.SurfaceBorder
import ru.qmods.client.presentation.theme.TextPrimary
import ru.qmods.client.presentation.theme.TextSecondary

@Composable
fun DeviceScreen(
    viewModel: DeviceViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(state.unlinkSuccessMessage) {
        if (state.unlinkSuccessMessage != null) {
            viewModel.consumeSuccessMessage()
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Text(
            text = stringResource(id = R.string.device_title),
            style = MaterialTheme.typography.headlineMedium,
            color = TextPrimary,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp)
        )

        when {
            state.isLoading -> SkeletonList(modifier = Modifier.padding(horizontal = 20.dp), itemCount = 1)

            state.errorMessage != null && state.device == null -> ErrorState(
                message = state.errorMessage.orEmpty(),
                type = state.errorType ?: ErrorType.UNKNOWN,
                onRetry = viewModel::refresh,
                modifier = Modifier.fillMaxSize()
            )

            state.device == null -> EmptyState(message = stringResource(id = R.string.device_no_device))

            else -> RefreshableScreen(isRefreshing = state.isRefreshing, onRefresh = viewModel::refresh) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 20.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    DeviceDetailsCard(state.device!!)

                    SolidCard(modifier = Modifier.fillMaxWidth()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { viewModel.requestUnlink() }
                        ) {
                            Icon(Icons.Rounded.LinkOff, contentDescription = null, tint = ErrorRed)
                            Spacer(modifier = Modifier.width(12.dp))
                            Text(
                                text = stringResource(id = R.string.device_unlink_button),
                                style = MaterialTheme.typography.titleMedium,
                                color = ErrorRed
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(24.dp))
                }
            }
        }
    }

    if (state.showUnlinkConfirm) {
        ConfirmDialog(
            title = stringResource(id = R.string.device_unlink_confirm_title),
            text = stringResource(id = R.string.device_unlink_confirm_text),
            confirmLabel = stringResource(id = R.string.device_unlink_button),
            onConfirm = viewModel::confirmUnlink,
            onDismiss = viewModel::dismissUnlinkConfirm,
            isLoading = state.isUnlinking
        )
    }
}

@Composable
private fun DeviceDetailsCard(device: Device) {
    SolidCard(modifier = Modifier.fillMaxWidth()) {
        Column {
            DeviceInfoRow(Icons.Rounded.Fingerprint, "ID устройства", device.deviceId)
            DeviceDivider()
            DeviceInfoRow(Icons.Rounded.PhoneAndroid, "Модель", device.model)
            DeviceDivider()
            DeviceInfoRow(Icons.Rounded.Android, "Версия Android", device.androidVersion)
            DeviceDivider()
            DeviceInfoRow(Icons.Rounded.History, "Версия клиента", device.clientVersion)
            device.linkedAt?.let {
                DeviceDivider()
                DeviceInfoRow(Icons.Rounded.CalendarToday, "Дата привязки", it)
            }
            device.lastSeenAt?.let {
                DeviceDivider()
                DeviceInfoRow(Icons.Rounded.History, "Последний запуск", it)
            }
        }
    }
}

@Composable
private fun DeviceDivider() {
    HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp), color = SurfaceBorder)
}

@Composable
private fun DeviceInfoRow(icon: ImageVector, label: String, value: String) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Icon(icon, contentDescription = null, tint = AccentCyan)
        Spacer(modifier = Modifier.width(12.dp))
        Column {
            Text(text = label, style = MaterialTheme.typography.labelMedium, color = TextSecondary)
            Text(text = value, style = MaterialTheme.typography.bodyMedium, color = TextPrimary)
        }
    }
}
