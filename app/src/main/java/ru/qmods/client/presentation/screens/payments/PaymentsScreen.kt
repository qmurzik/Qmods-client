package ru.qmods.client.presentation.screens.payments

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
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
import ru.qmods.client.domain.model.Payment
import ru.qmods.client.domain.model.PaymentStatus
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.presentation.components.EmptyState
import ru.qmods.client.presentation.components.ErrorState
import ru.qmods.client.presentation.components.SkeletonList
import ru.qmods.client.presentation.components.SolidCard
import ru.qmods.client.presentation.components.StatusBadge
import ru.qmods.client.presentation.theme.ErrorRed
import ru.qmods.client.presentation.theme.SuccessGreen
import ru.qmods.client.presentation.theme.TextPrimary
import ru.qmods.client.presentation.theme.TextSecondary
import ru.qmods.client.presentation.theme.TextTertiary
import ru.qmods.client.presentation.theme.WarningAmber

@Composable
fun PaymentsScreen(
    viewModel: PaymentsViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    Column(modifier = Modifier.fillMaxSize()) {
        Text(
            text = stringResource(id = R.string.payments_title),
            style = MaterialTheme.typography.headlineMedium,
            color = TextPrimary,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp)
        )

        when {
            state.isLoading -> SkeletonList(modifier = Modifier.padding(horizontal = 20.dp))

            state.errorMessage != null && state.payments.isEmpty() -> ErrorState(
                message = state.errorMessage.orEmpty(),
                type = state.errorType ?: ErrorType.UNKNOWN,
                onRetry = viewModel::refresh,
                modifier = Modifier.fillMaxSize()
            )

            state.payments.isEmpty() -> EmptyState(message = stringResource(id = R.string.payments_empty))

            else -> LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 20.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                itemsIndexed(state.payments, key = { index, item -> item.id.ifBlank { index.toString() } }) { _, payment ->
                    PaymentRow(payment)
                }
            }
        }
    }
}

@Composable
private fun PaymentRow(payment: Payment) {
    SolidCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth()
        ) {
            Column {
                Text(
                    text = payment.planName ?: "Платёж",
                    style = MaterialTheme.typography.titleMedium,
                    color = TextPrimary
                )
                Text(
                    text = payment.date,
                    style = MaterialTheme.typography.bodySmall,
                    color = TextTertiary
                )
            }

            Column(horizontalAlignment = Alignment.End) {
                Text(
                    text = "${payment.amount.toDisplayAmount()} ${payment.currency}",
                    style = MaterialTheme.typography.titleMedium,
                    color = TextPrimary
                )
                val (label, color) = payment.status.toLabelAndColor()
                StatusBadge(text = label, color = color, modifier = Modifier.padding(top = 4.dp))
            }
        }
    }
}

private fun Double.toDisplayAmount(): String =
    if (this == this.toLong().toDouble()) this.toLong().toString() else this.toString()

private fun PaymentStatus.toLabelAndColor(): Pair<String, androidx.compose.ui.graphics.Color> = when (this) {
    PaymentStatus.SUCCESS -> "Оплачено" to SuccessGreen
    PaymentStatus.PENDING -> "В обработке" to WarningAmber
    PaymentStatus.FAILED -> "Ошибка" to ErrorRed
    PaymentStatus.UNKNOWN -> "Неизвестно" to TextSecondary
}
