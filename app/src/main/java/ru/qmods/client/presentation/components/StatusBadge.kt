package ru.qmods.client.presentation.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import ru.qmods.client.presentation.theme.ErrorRed
import ru.qmods.client.presentation.theme.SuccessGreen
import ru.qmods.client.presentation.theme.WarningAmber

@Composable
fun StatusBadge(
    text: String,
    color: Color,
    modifier: Modifier = Modifier
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .background(color.copy(alpha = 0.16f), RoundedCornerShape(100.dp))
            .padding(horizontal = 12.dp, vertical = 6.dp)
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .background(color, CircleShape)
        )
        Spacer(modifier = Modifier.width(6.dp))
        Text(
            text = text,
            style = MaterialTheme.typography.labelMedium,
            color = color
        )
    }
}

enum class SubscriptionStatusKind { ACTIVE, INACTIVE, EXPIRING }

@Composable
fun SubscriptionStatusBadge(kind: SubscriptionStatusKind, modifier: Modifier = Modifier) {
    val (label, color) = when (kind) {
        SubscriptionStatusKind.ACTIVE -> "Активна" to SuccessGreen
        SubscriptionStatusKind.EXPIRING -> "Истекает" to WarningAmber
        SubscriptionStatusKind.INACTIVE -> "Не активна" to ErrorRed
    }
    StatusBadge(text = label, color = color, modifier = modifier)
}
