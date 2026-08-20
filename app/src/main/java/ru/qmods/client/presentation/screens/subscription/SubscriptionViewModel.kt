package ru.qmods.client.presentation.screens.subscription

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import ru.qmods.client.domain.model.Subscription
import ru.qmods.client.domain.usecase.GetSubscriptionUseCase
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.domain.util.Resource
import javax.inject.Inject

data class SubscriptionUiState(
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val subscription: Subscription? = null,
    val errorMessage: String? = null,
    val errorType: ErrorType? = null
)

@HiltViewModel
class SubscriptionViewModel @Inject constructor(
    private val getSubscriptionUseCase: GetSubscriptionUseCase
) : ViewModel() {

    private val _uiState = MutableStateFlow(SubscriptionUiState())
    val uiState: StateFlow<SubscriptionUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun refresh() = load(isRefresh = true)

    private fun load(isRefresh: Boolean = false) {
        viewModelScope.launch {
            _uiState.update {
                if (isRefresh) it.copy(isRefreshing = true) else it.copy(isLoading = true)
            }

            when (val result = getSubscriptionUseCase()) {
                is Resource.Success -> _uiState.update {
                    it.copy(isLoading = false, isRefreshing = false, subscription = result.data, errorMessage = null)
                }
                is Resource.Error -> _uiState.update {
                    it.copy(
                        isLoading = false,
                        isRefreshing = false,
                        errorMessage = if (it.subscription == null) result.message else null,
                        errorType = result.type
                    )
                }
                is Resource.Loading -> Unit
            }
        }
    }
}
