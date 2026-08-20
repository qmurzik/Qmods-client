package ru.qmods.client.presentation.screens.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CreditCard
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.PhoneAndroid
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ru.qmods.client.R
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.presentation.components.ErrorState
import ru.qmods.client.presentation.components.GradientCard
import ru.qmods.client.presentation.components.RefreshableScreen
import ru.qmods.client.presentation.components.SkeletonList
import ru.qmods.client.presentation.components.SolidCard
import ru.qmods.client.presentation.components.SubscriptionStatusBadge
import ru.qmods.client.presentation.components.SubscriptionStatusKind
import ru.qmods.client.presentation.theme.QModsGradients
import ru.qmods.client.presentation.theme.TextOnAccent
import ru.qmods.client.presentation.theme.TextPrimary
import ru.qmods.client.presentation.theme.TextSecondary

@Composable
fun HomeScreen(
    onNavigateToNotifications: () -> Unit,
    onNavigateToSubscription: () -> Unit,
    onNavigateToDevice: () -> Unit,
    onNavigateToPayments: () -> Unit,
    viewModel: HomeViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "QMods",
                style = MaterialTheme.typography.headlineMedium,
                color = TextPrimary,
                fontWeight = FontWeight.Bold
            )
            IconButton(onClick = onNavigateToNotifications) {
                Icon(
                    imageVector = Icons.Rounded.Notifications,
                    contentDescription = stringResource(id = R.string.notifications_title),
                    tint = TextPrimary
                )
            }
        }

        when {
            state.isLoading -> SkeletonList(modifier = Modifier.padding(horizontal = 20.dp))

            state.errorMessage != null && state.user == null -> ErrorState(
                message = state.errorMessage.orEmpty(),
                type = state.errorType ?: ErrorType.UNKNOWN,
                onRetry = viewModel::refresh,
                modifier = Modifier.fillMaxSize()
            )

            else -> RefreshableScreen(
                isRefreshing = state.isRefreshing,
                onRefresh = viewModel::refresh
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 20.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    UserSummaryCard(
                        login = state.user?.login.orEmpty(),
                        isSubscriptionActive = state.subscription?.isActive == true,
                        daysLeft = state.subscription?.daysLeft ?: 0
                    )

                    Text(
                        text = "Быстрые действия",
                        style = MaterialTheme.typography.titleMedium,
                        color = TextPrimary
                    )

                    QuickActionsGrid(
                        onSubscription = onNavigateToSubscription,
                        onDevice = onNavigateToDevice,
                        onPayments = onNavigateToPayments
                    )

                    Spacer(modifier = Modifier.height(24.dp))
                }
            }
        }
    }
}

@Composable
private fun UserSummaryCard(
    login: String,
    isSubscriptionActive: Boolean,
    daysLeft: Int
) {
    GradientCard(
        backgroundBrush = QModsGradients.primaryBrand,
        borderColor = Color.Transparent,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(56.dp)
                        .background(Color.White.copy(alpha = 0.18f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Rounded.Person, contentDescription = null, tint = TextOnAccent)
                }
                Spacer(modifier = Modifier.width(14.dp))
                Column {
                    Text(
                        text = login.ifBlank { "..." },
                        style = MaterialTheme.typography.titleLarge,
                        color = TextOnAccent,
                        fontWeight = FontWeight.SemiBold
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    SubscriptionStatusBadge(
                        kind = if (isSubscriptionActive) SubscriptionStatusKind.ACTIVE else SubscriptionStatusKind.INACTIVE
                    )
                }
            }

            if (isSubscriptionActive) {
                Spacer(modifier = Modifier.height(18.dp))
                Text(
                    text = stringResource(id = R.string.subscription_days_left, daysLeft),
                    style = MaterialTheme.typography.bodyMedium,
                    color = TextOnAccent.copy(alpha = 0.9f)
                )
            }
        }
    }
}

@Composable
private fun QuickActionsGrid(
    onSubscription: () -> Unit,
    onDevice: () -> Unit,
    onPayments: () -> Unit
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        QuickActionCard(
            icon = Icons.Rounded.WorkspacePremium,
            label = stringResource(id = R.string.nav_subscription),
            onClick = onSubscription,
            modifier = Modifier.weight(1f)
        )
        QuickActionCard(
            icon = Icons.Rounded.PhoneAndroid,
            label = stringResource(id = R.string.nav_device),
            onClick = onDevice,
            modifier = Modifier.weight(1f)
        )
        QuickActionCard(
            icon = Icons.Rounded.CreditCard,
            label = stringResource(id = R.string.nav_payments),
            onClick = onPayments,
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun QuickActionCard(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    SolidCard(modifier = modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
            Icon(icon, contentDescription = label, tint = TextPrimary)
            Spacer(modifier = Modifier.height(8.dp))
            Text(text = label, style = MaterialTheme.typography.labelMedium, color = TextSecondary)
        }
    }
}
