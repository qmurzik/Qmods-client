package ru.qmods.client.data.repository

import kotlinx.coroutines.flow.Flow
import ru.qmods.client.data.api.QModsApiService
import ru.qmods.client.data.local.SessionManager
import ru.qmods.client.data.model.LoginRequestDto
import ru.qmods.client.data.util.safeApiCall
import ru.qmods.client.domain.model.DeviceInfo
import ru.qmods.client.domain.repository.AuthRepository
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.domain.util.Resource
import ru.qmods.client.util.ConnectivityObserver
import javax.inject.Inject

class AuthRepositoryImpl @Inject constructor(
    private val api: QModsApiService,
    private val sessionManager: SessionManager,
    private val connectivityObserver: ConnectivityObserver
) : AuthRepository {

    override val isLoggedIn: Flow<Boolean> = sessionManager.isLoggedIn

    override suspend fun login(login: String, password: String, deviceInfo: DeviceInfo): Resource<Unit> {
        val result = safeApiCall(connectivityObserver) {
            api.login(
                LoginRequestDto(
                    login = login,
                    password = password,
                    deviceId = deviceInfo.deviceId,
                    deviceModel = deviceInfo.deviceModel,
                    androidVersion = deviceInfo.androidVersion,
                    clientVersion = deviceInfo.clientVersion
                )
            )
        }

        return when (result) {
            is Resource.Success -> {
                val body = result.data
                val token = body.sessionToken
                if (body.success && !token.isNullOrBlank()) {
                    sessionManager.saveSessionToken(token)
                    Resource.Success(Unit)
                } else {
                    Resource.Error(
                        body.message ?: "Неверный логин или пароль",
                        ErrorType.SERVER
                    )
                }
            }
            is Resource.Error -> Resource.Error(result.message, result.type)
            is Resource.Loading -> Resource.Loading()
        }
    }

    /**
     * Best-effort server-side session invalidation - logout must never get stuck because the
     * network is down, so any failure here is swallowed and the local session is cleared
     * regardless.
     */
    override suspend fun logout() {
        runCatching { api.logout() }
        sessionManager.clearSession()
    }

    override suspend fun clearSession() {
        sessionManager.clearSession()
    }
}
