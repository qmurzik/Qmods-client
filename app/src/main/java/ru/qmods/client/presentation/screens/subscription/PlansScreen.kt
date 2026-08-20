package ru.qmods.client.presentation.screens.subscription

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import ru.qmods.client.domain.model.Plan
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.presentation.components.EmptyState
import ru.qmods.client.presentation.components.ErrorState
import ru.qmods.client.presentation.components.GradientCard
import ru.qmods.client.presentation.components.SkeletonList
import ru.qmods.client.presentation.components.SolidCard
import ru.qmods.client.presentation.theme.AccentGold
import ru.qmods.client.presentation.theme.QModsGradients
import ru.qmods.client.presentation.theme.TextOnAccent
import ru.qmods.client.presentation.theme.TextPrimary
import ru.qmods.client.presentation.theme.TextSecondary

@Composable
fun PlansScreen(
    onBack: () -> Unit,
    viewModel: PlansViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 8.dp)
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.Rounded.ArrowBack, contentDescription = null, tint = TextPrimary)
            }
            Text(
                text = stringResource(id = R.string.subscription_plans_title),
                style = MaterialTheme.typography.headlineMedium,
                color = TextPrimary,
                fontWeight = FontWeight.Bold
            )
        }

        when {
            state.isLoading -> SkeletonList(modifier = Modifier.padding(horizontal = 20.dp))

            state.errorMessage != null && state.plans.isEmpty() -> ErrorState(
                message = state.errorMessage.orEmpty(),
                type = state.errorType ?: ErrorType.UNKNOWN,
                onRetry = viewModel::refresh,
                modifier = Modifier.fillMaxSize()
            )

            state.plans.isEmpty() -> EmptyState(message = stringResource(id = R.string.common_empty))

            else -> LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                items(state.plans, key = { it.id }) { plan ->
                    PlanCard(plan)
                }
            }
        }
    }
}

@Composable
private fun PlanCard(plan: Plan) {
    val content: @Composable () -> Unit = {
        Column {
            Row(
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = plan.name,
                    style = MaterialTheme.typography.titleLarge,
                    color = if (plan.isPopular) TextOnAccent else TextPrimary,
                    fontWeight = FontWeight.SemiBold
                )
                if (plan.isPopular) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .background(TextOnAccent.copy(alpha = 0.2f), RoundedCornerShape(100.dp))
                            .padding(horizontal = 10.dp, vertical = 4.dp)
                    ) {
                        Icon(Icons.Rounded.Star, contentDescription = null, tint = AccentGold, modifier = Modifier.height(14.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(text = "Популярный", style = MaterialTheme.typography.labelSmall, color = TextOnAccent)
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            Text(
                text = "${plan.price.toDisplayString()} ${plan.currency}",
                style = MaterialTheme.typography.displayMedium,
                color = if (plan.isPopular) TextOnAccent else TextPrimary
            )

            Spacer(modifier = Modifier.height(4.dp))

            Text(
                text = "на ${plan.durationDays} дней",
                style = MaterialTheme.typography.bodyMedium,
                color = if (plan.isPopular) TextOnAccent.copy(alpha = 0.85f) else TextSecondary
            )
        }
    }

    if (plan.isPopular) {
        GradientCard(backgroundBrush = QModsGradients.primaryBrand, borderColor = androidx.compose.ui.graphics.Color.Transparent, modifier = Modifier.fillMaxWidth()) {
            content()
        }
    } else {
        SolidCard(modifier = Modifier.fillMaxWidth()) {
            content()
        }
    }
}

private fun Double.toDisplayString(): String =
    if (this == this.toLong().toDouble()) this.toLong().toString() else this.toString()
