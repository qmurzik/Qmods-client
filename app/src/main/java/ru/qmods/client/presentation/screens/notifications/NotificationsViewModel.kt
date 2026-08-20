package ru.qmods.client.presentation.screens.notifications

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import ru.qmods.client.domain.model.AppNotification
import ru.qmods.client.domain.usecase.GetNotificationsUseCase
import ru.qmods.client.domain.usecase.MarkNotificationReadUseCase
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.domain.util.Resource
import javax.inject.Inject

data class NotificationsUiState(
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val notifications: List<AppNotification> = emptyList(),
    val errorMessage: String? = null,
    val errorType: ErrorType? = null
)

@HiltViewModel
class NotificationsViewModel @Inject constructor(
    private val getNotificationsUseCase: GetNotificationsUseCase,
    private val markNotificationReadUseCase: MarkNotificationReadUseCase
) : ViewModel() {

    private val _uiState = MutableStateFlow(NotificationsUiState())
    val uiState: StateFlow<NotificationsUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun refresh() = load(isRefresh = true)

    fun markAsRead(id: String) {
        val target = _uiState.value.notifications.firstOrNull { it.id == id } ?: return
        if (target.isRead) return

        _uiState.update { state ->
            state.copy(notifications = state.notifications.map { if (it.id == id) it.copy(isRead = true) else it })
        }

        viewModelScope.launch {
            markNotificationReadUseCase(id)
        }
    }

    private fun load(isRefresh: Boolean = false) {
        viewModelScope.launch {
            _uiState.update {
                if (isRefresh) it.copy(isRefreshing = true) else it.copy(isLoading = true)
            }

            when (val result = getNotificationsUseCase()) {
                is Resource.Success -> _uiState.update {
                    it.copy(isLoading = false, isRefreshing = false, notifications = result.data, errorMessage = null)
                }
                is Resource.Error -> _uiState.update {
                    it.copy(
                        isLoading = false,
                        isRefreshing = false,
                        errorMessage = if (it.notifications.isEmpty()) result.message else null,
                        errorType = result.type
                    )
                }
                is Resource.Loading -> Unit
            }
        }
    }
}
