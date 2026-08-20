package ru.qmods.client.presentation.screens.profile

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
import androidx.compose.material.icons.rounded.CalendarToday
import androidx.compose.material.icons.rounded.Logout
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ru.qmods.client.R
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.presentation.components.ConfirmDialog
import ru.qmods.client.presentation.components.ErrorState
import ru.qmods.client.presentation.components.GradientCard
import ru.qmods.client.presentation.components.RefreshableScreen
import ru.qmods.client.presentation.components.SkeletonList
import ru.qmods.client.presentation.components.SolidCard
import ru.qmods.client.presentation.theme.ErrorRed
import ru.qmods.client.presentation.theme.QModsGradients
import ru.qmods.client.presentation.theme.TextOnAccent
import ru.qmods.client.presentation.theme.TextPrimary
import ru.qmods.client.presentation.theme.TextSecondary

@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    Column(modifier = Modifier.fillMaxSize()) {
        Text(
            text = stringResource(id = R.string.profile_title),
            style = MaterialTheme.typography.headlineMedium,
            color = TextPrimary,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp)
        )

        when {
            state.isLoading -> SkeletonList(modifier = Modifier.padding(horizontal = 20.dp), itemCount = 1)

            state.errorMessage != null && state.user == null -> ErrorState(
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
                    GradientCard(backgroundBrush = QModsGradients.primaryBrand, borderColor = Color.Transparent, modifier = Modifier.fillMaxWidth()) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                modifier = Modifier
                                    .size(64.dp)
                                    .background(Color.White.copy(alpha = 0.18f), CircleShape),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(Icons.Rounded.Person, contentDescription = null, tint = TextOnAccent)
                            }
                            Spacer(modifier = Modifier.width(16.dp))
                            Column {
                                Text(
                                    text = state.user?.login.orEmpty(),
                                    style = MaterialTheme.typography.titleLarge,
                                    color = TextOnAccent,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                        }
                    }

                    state.user?.registeredAt?.let {
                        SolidCard(modifier = Modifier.fillMaxWidth()) {
                            ProfileInfoRow(Icons.Rounded.CalendarToday, "Дата регистрации", it)
                        }
                    }

                    SolidCard(modifier = Modifier.fillMaxWidth()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { viewModel.requestLogout() }
                        ) {
                            Icon(Icons.Rounded.Logout, contentDescription = null, tint = ErrorRed)
                            Spacer(modifier = Modifier.width(12.dp))
                            Text(
                                text = stringResource(id = R.string.common_logout),
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

    if (state.showLogoutConfirm) {
        ConfirmDialog(
            title = stringResource(id = R.string.common_logout),
            text = "Вы уверены, что хотите выйти из аккаунта?",
            confirmLabel = stringResource(id = R.string.common_logout),
            onConfirm = viewModel::confirmLogout,
            onDismiss = viewModel::dismissLogoutConfirm
        )
    }
}

@Composable
private fun ProfileInfoRow(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, value: String) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Icon(icon, contentDescription = null, tint = TextSecondary)
        Spacer(modifier = Modifier.width(12.dp))
        Column {
            Text(text = label, style = MaterialTheme.typography.labelMedium, color = TextSecondary)
            Text(text = value, style = MaterialTheme.typography.bodyMedium, color = TextPrimary)
        }
    }
}
