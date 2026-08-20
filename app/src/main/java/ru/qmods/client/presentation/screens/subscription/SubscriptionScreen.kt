package ru.qmods.client.presentation.screens.subscription

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
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ru.qmods.client.R
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.presentation.components.ErrorState
import ru.qmods.client.presentation.components.GradientCard
import ru.qmods.client.presentation.components.PrimaryButton
import ru.qmods.client.presentation.components.RefreshableScreen
import ru.qmods.client.presentation.components.SkeletonList
import ru.qmods.client.presentation.components.SubscriptionStatusBadge
import ru.qmods.client.presentation.components.SubscriptionStatusKind
import ru.qmods.client.presentation.theme.AccentCyan
import ru.qmods.client.presentation.theme.TextPrimary
import ru.qmods.client.presentation.theme.TextSecondary

@Composable
fun SubscriptionScreen(
    onNavigateToPlans: () -> Unit,
    viewModel: SubscriptionViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    Column(modifier = Modifier.fillMaxSize()) {
        Text(
            text = stringResource(id = R.string.nav_subscription),
            style = MaterialTheme.typography.headlineMedium,
            color = TextPrimary,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp)
        )

        when {
            state.isLoading -> SkeletonList(modifier = Modifier.padding(horizontal = 20.dp))

            state.errorMessage != null && state.subscription == null -> ErrorState(
                message = state.errorMessage.orEmpty(),
                type = state.errorType ?: ErrorType.UNKNOWN,
                onRetry = viewModel::refresh,
                modifier = Modifier.fillMaxSize()
            )

            else -> RefreshableScreen(isRefreshing = state.isRefreshing, onRefresh = viewModel::refresh) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 20.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    val subscription = state.subscription
                    GradientCard(modifier = Modifier.fillMaxWidth()) {
                        Column {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Rounded.WorkspacePremium, contentDescription = null, tint = AccentCyan)
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(
                                        text = subscription?.planName ?: stringResource(id = R.string.subscription_inactive),
                                        style = MaterialTheme.typography.titleLarge,
                                        color = TextPrimary
                                    )
                                }
                                SubscriptionStatusBadge(
                                    kind = if (subscription?.isActive == true) SubscriptionStatusKind.ACTIVE else SubscriptionStatusKind.INACTIVE
                                )
                            }

                            if (subscription?.isActive == true) {
                                Spacer(modifier = Modifier.height(20.dp))
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Rounded.CalendarMonth, contentDescription = null, tint = TextSecondary)
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(
                                        text = subscription.expiresAt?.let {
                                            stringResource(id = R.string.subscription_expires_on, it)
                                        } ?: "",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = TextSecondary
                                    )
                                }
                                Spacer(modifier = Modifier.height(6.dp))
                                Text(
                                    text = stringResource(id = R.string.subscription_days_left, subscription.daysLeft),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = TextSecondary
                                )
                            }
                        }
                    }

                    PrimaryButton(
                        text = stringResource(id = R.string.subscription_choose_plan),
                        onClick = onNavigateToPlans
                    )

                    Spacer(modifier = Modifier.height(24.dp))
                }
            }
        }
    }
}
