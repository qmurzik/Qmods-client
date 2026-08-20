package ru.qmods.client.presentation.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CloudOff
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.Inbox
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import ru.qmods.client.R
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.presentation.theme.ErrorRed
import ru.qmods.client.presentation.theme.TextSecondary
import ru.qmods.client.presentation.theme.WarningAmber

@Composable
fun ErrorState(
    message: String,
    modifier: Modifier = Modifier,
    type: ErrorType = ErrorType.UNKNOWN,
    onRetry: (() -> Unit)? = null
) {
    val (icon, tint) = when (type) {
        ErrorType.NO_INTERNET -> Icons.Rounded.CloudOff to TextSecondary
        ErrorType.SESSION_EXPIRED -> Icons.Rounded.Lock to WarningAmber
        ErrorType.SERVER -> Icons.Rounded.ErrorOutline to ErrorRed
        ErrorType.UNKNOWN -> Icons.Rounded.ErrorOutline to ErrorRed
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(56.dp)
        )
        Text(
            text = message,
            style = MaterialTheme.typography.bodyLarge,
            color = TextSecondary,
            textAlign = TextAlign.Center
        )
        if (onRetry != null) {
            PrimaryButton(
                text = stringResource(id = R.string.common_retry),
                onClick = onRetry,
                modifier = Modifier.padding(top = 4.dp)
            )
        }
    }
}

@Composable
fun EmptyState(
    message: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(
            imageVector = Icons.Rounded.Inbox,
            contentDescription = null,
            tint = TextSecondary,
            modifier = Modifier.size(48.dp)
        )
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = TextSecondary,
            textAlign = TextAlign.Center
        )
    }
}
