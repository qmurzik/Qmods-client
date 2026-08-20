package ru.qmods.client.presentation.screens.device

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import ru.qmods.client.domain.model.Device
import ru.qmods.client.domain.usecase.GetDeviceUseCase
import ru.qmods.client.domain.usecase.UnlinkDeviceUseCase
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.domain.util.Resource
import javax.inject.Inject

data class DeviceUiState(
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val device: Device? = null,
    val errorMessage: String? = null,
    val errorType: ErrorType? = null,
    val showUnlinkConfirm: Boolean = false,
    val isUnlinking: Boolean = false,
    val unlinkSuccessMessage: String? = null
)

@HiltViewModel
class DeviceViewModel @Inject constructor(
    private val getDeviceUseCase: GetDeviceUseCase,
    private val unlinkDeviceUseCase: UnlinkDeviceUseCase
) : ViewModel() {

    private val _uiState = MutableStateFlow(DeviceUiState())
    val uiState: StateFlow<DeviceUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun refresh() = load(isRefresh = true)

    fun requestUnlink() {
        _uiState.update { it.copy(showUnlinkConfirm = true) }
    }

    fun dismissUnlinkConfirm() {
        _uiState.update { it.copy(showUnlinkConfirm = false) }
    }

    fun confirmUnlink() {
        viewModelScope.launch {
            _uiState.update { it.copy(isUnlinking = true) }

            when (val result = unlinkDeviceUseCase()) {
                is Resource.Success -> _uiState.update {
                    it.copy(
                        isUnlinking = false,
                        showUnlinkConfirm = false,
                        device = null,
                        unlinkSuccessMessage = "Устройство успешно отвязано"
                    )
                }
                is Resource.Error -> _uiState.update {
                    it.copy(isUnlinking = false, showUnlinkConfirm = false, errorMessage = result.message, errorType = result.type)
                }
                is Resource.Loading -> Unit
            }
        }
    }

    fun consumeSuccessMessage() {
        _uiState.update { it.copy(unlinkSuccessMessage = null) }
    }

    private fun load(isRefresh: Boolean = false) {
        viewModelScope.launch {
            _uiState.update {
                if (isRefresh) it.copy(isRefreshing = true) else it.copy(isLoading = true)
            }

            when (val result = getDeviceUseCase()) {
                is Resource.Success -> _uiState.update {
                    it.copy(isLoading = false, isRefreshing = false, device = result.data, errorMessage = null)
                }
                is Resource.Error -> _uiState.update {
                    it.copy(isLoading = false, isRefreshing = false, errorMessage = result.message, errorType = result.type)
                }
                is Resource.Loading -> Unit
            }
        }
    }
}
