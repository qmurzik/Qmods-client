package ru.qmods.client.domain.repository

import kotlinx.coroutines.flow.Flow
import ru.qmods.client.domain.model.DeviceInfo
import ru.qmods.client.domain.util.Resource

interface AuthRepository {
    val isLoggedIn: Flow<Boolean>

    suspend fun login(login: String, password: String, deviceInfo: DeviceInfo): Resource<Unit>

    suspend fun logout()

    /** Clears the local session without a network call, e.g. after a 401 from any endpoint. */
    suspend fun clearSession()
}
