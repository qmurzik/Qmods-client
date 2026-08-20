package ru.qmods.client.presentation.screens.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import ru.qmods.client.domain.model.User
import ru.qmods.client.domain.usecase.GetProfileUseCase
import ru.qmods.client.domain.usecase.LogoutUseCase
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.domain.util.Resource
import javax.inject.Inject

data class ProfileUiState(
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val user: User? = null,
    val errorMessage: String? = null,
    val errorType: ErrorType? = null,
    val showLogoutConfirm: Boolean = false
)

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val getProfileUseCase: GetProfileUseCase,
    private val logoutUseCase: LogoutUseCase
) : ViewModel() {

    private val _uiState = MutableStateFlow(ProfileUiState())
    val uiState: StateFlow<ProfileUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun refresh() = load(isRefresh = true)

    fun requestLogout() {
        _uiState.update { it.copy(showLogoutConfirm = true) }
    }

    fun dismissLogoutConfirm() {
        _uiState.update { it.copy(showLogoutConfirm = false) }
    }

    /** Clearing the session flips AuthRepository.isLoggedIn to false, which the nav graph
     *  observes to send the user back to the login screen - no explicit navigation call here. */
    fun confirmLogout() {
        viewModelScope.launch { logoutUseCase() }
    }

    private fun load(isRefresh: Boolean = false) {
        viewModelScope.launch {
            _uiState.update {
                if (isRefresh) it.copy(isRefreshing = true) else it.copy(isLoading = true)
            }

            when (val result = getProfileUseCase()) {
                is Resource.Success -> _uiState.update {
                    it.copy(isLoading = false, isRefreshing = false, user = result.data, errorMessage = null)
                }
                is Resource.Error -> _uiState.update {
                    it.copy(isLoading = false, isRefreshing = false, errorMessage = result.message, errorType = result.type)
                }
                is Resource.Loading -> Unit
            }
        }
    }
}
