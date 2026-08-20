package ru.qmods.client.presentation.screens.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import ru.qmods.client.domain.model.Subscription
import ru.qmods.client.domain.model.User
import ru.qmods.client.domain.usecase.GetProfileUseCase
import ru.qmods.client.domain.usecase.GetSubscriptionUseCase
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.domain.util.Resource
import javax.inject.Inject

data class HomeUiState(
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val user: User? = null,
    val subscription: Subscription? = null,
    val errorMessage: String? = null,
    val errorType: ErrorType? = null
)

@HiltViewModel
class HomeViewModel @Inject constructor(
    private val getProfileUseCase: GetProfileUseCase,
    private val getSubscriptionUseCase: GetSubscriptionUseCase
) : ViewModel() {

    private val _uiState = MutableStateFlow(HomeUiState())
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun refresh() = load(isRefresh = true)

    private fun load(isRefresh: Boolean = false) {
        viewModelScope.launch {
            _uiState.update {
                if (isRefresh) it.copy(isRefreshing = true) else it.copy(isLoading = true)
            }

            // Independent requests - fire together instead of paying two round-trips back to back.
            val (profileResult, subscriptionResult) = coroutineScope {
                val profileDeferred = async { getProfileUseCase() }
                val subscriptionDeferred = async { getSubscriptionUseCase() }
                profileDeferred.await() to subscriptionDeferred.await()
            }

            val user = (profileResult as? Resource.Success)?.data
            val subscription = (subscriptionResult as? Resource.Success)?.data

            val firstError = (profileResult as? Resource.Error)
                ?: (subscriptionResult as? Resource.Error)

            _uiState.update {
                it.copy(
                    isLoading = false,
                    isRefreshing = false,
                    user = user ?: it.user,
                    subscription = subscription ?: it.subscription,
                    errorMessage = if (user == null && subscription == null) firstError?.message else null,
                    errorType = if (user == null && subscription == null) firstError?.type else null
                )
            }
        }
    }
}
