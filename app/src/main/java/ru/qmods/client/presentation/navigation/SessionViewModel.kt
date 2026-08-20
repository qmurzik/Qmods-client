package ru.qmods.client.presentation.navigation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import ru.qmods.client.domain.usecase.ObserveSessionUseCase
import javax.inject.Inject

/**
 * Mirrors AuthRepository.isLoggedIn for the whole nav graph, so a session that dies anywhere
 * (manual logout, or a 401 caught by AuthInterceptor) is reflected by a single redirect to
 * the login screen instead of every screen having to know about auth state.
 */
@HiltViewModel
class SessionViewModel @Inject constructor(
    observeSessionUseCase: ObserveSessionUseCase
) : ViewModel() {

    val isLoggedIn: StateFlow<Boolean?> = observeSessionUseCase()
        .stateIn(viewModelScope, SharingStarted.Eagerly, null)
}
