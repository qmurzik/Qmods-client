package ru.qmods.client.presentation.screens.subscription

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import ru.qmods.client.domain.model.Plan
import ru.qmods.client.domain.usecase.GetPlansUseCase
import ru.qmods.client.domain.usecase.RenewSubscriptionUseCase
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.domain.util.Resource
import javax.inject.Inject

data class PlansUiState(
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val plans: List<Plan> = emptyList(),
    val errorMessage: String? = null,
    val errorType: ErrorType? = null,
    val purchasingPlanId: String? = null,
    val purchaseErrorMessage: String? = null,
    val paymentUrlToOpen: String? = null
)

@HiltViewModel
class PlansViewModel @Inject constructor(
    private val getPlansUseCase: GetPlansUseCase,
    private val renewSubscriptionUseCase: RenewSubscriptionUseCase
) : ViewModel() {

    private val _uiState = MutableStateFlow(PlansUiState())
    val uiState: StateFlow<PlansUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun refresh() = load(isRefresh = true)

    fun purchase(planId: String) {
        if (_uiState.value.purchasingPlanId != null) return

        viewModelScope.launch {
            _uiState.update { it.copy(purchasingPlanId = planId, purchaseErrorMessage = null) }

            when (val result = renewSubscriptionUseCase(planId)) {
                is Resource.Success -> _uiState.update {
                    it.copy(purchasingPlanId = null, paymentUrlToOpen = result.data.paymentUrl)
                }
                is Resource.Error -> _uiState.update {
                    it.copy(purchasingPlanId = null, purchaseErrorMessage = result.message)
                }
                is Resource.Loading -> Unit
            }
        }
    }

    fun consumePaymentUrl() {
        _uiState.update { it.copy(paymentUrlToOpen = null) }
    }

    fun dismissPurchaseError() {
        _uiState.update { it.copy(purchaseErrorMessage = null) }
    }

    private fun load(isRefresh: Boolean = false) {
        viewModelScope.launch {
            _uiState.update {
                if (isRefresh) it.copy(isRefreshing = true) else it.copy(isLoading = true)
            }

            when (val result = getPlansUseCase()) {
                is Resource.Success -> _uiState.update {
                    it.copy(isLoading = false, isRefreshing = false, plans = result.data, errorMessage = null)
                }
                is Resource.Error -> _uiState.update {
                    it.copy(
                        isLoading = false,
                        isRefreshing = false,
                        errorMessage = if (it.plans.isEmpty()) result.message else null,
                        errorType = result.type
                    )
                }
                is Resource.Loading -> Unit
            }
        }
    }
}
