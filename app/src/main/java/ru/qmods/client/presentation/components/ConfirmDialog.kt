package ru.qmods.client.presentation.components

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import ru.qmods.client.R
import ru.qmods.client.presentation.theme.ErrorRed
import ru.qmods.client.presentation.theme.SurfaceCard
import ru.qmods.client.presentation.theme.TextPrimary
import ru.qmods.client.presentation.theme.TextSecondary

@Composable
fun ConfirmDialog(
    title: String,
    text: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    isDestructive: Boolean = true,
    isLoading: Boolean = false
) {
    AlertDialog(
        onDismissRequest = { if (!isLoading) onDismiss() },
        containerColor = SurfaceCard,
        icon = {
            Icon(
                imageVector = Icons.Rounded.WarningAmber,
                contentDescription = null,
                tint = if (isDestructive) ErrorRed else TextPrimary,
                modifier = Modifier.size(32.dp)
            )
        },
        title = {
            Text(text = title, color = TextPrimary, style = MaterialTheme.typography.titleLarge)
        },
        text = {
            Text(text = text, color = TextSecondary, style = MaterialTheme.typography.bodyMedium)
        },
        confirmButton = {
            TextButton(onClick = onConfirm, enabled = !isLoading) {
                Text(
                    text = confirmLabel,
                    color = if (isDestructive) ErrorRed else TextPrimary,
                    style = MaterialTheme.typography.labelLarge
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isLoading) {
                Text(
                    text = stringResource(id = R.string.common_cancel),
                    color = TextSecondary,
                    style = MaterialTheme.typography.labelLarge
                )
            }
        }
    )
}
