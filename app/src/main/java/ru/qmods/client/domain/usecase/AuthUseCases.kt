package ru.qmods.client.domain.usecase

import kotlinx.coroutines.flow.Flow
import ru.qmods.client.domain.model.DeviceInfo
import ru.qmods.client.domain.repository.AuthRepository
import ru.qmods.client.domain.util.Resource
import javax.inject.Inject

class LoginUseCase @Inject constructor(
    private val repository: AuthRepository
) {
    suspend operator fun invoke(login: String, password: String, deviceInfo: DeviceInfo): Resource<Unit> {
        if (login.isBlank() || password.isBlank()) {
            return Resource.Error("Введите логин и пароль")
        }
        return repository.login(login.trim(), password, deviceInfo)
    }
}

class LogoutUseCase @Inject constructor(
    private val repository: AuthRepository
) {
    suspend operator fun invoke() = repository.logout()
}

class ObserveSessionUseCase @Inject constructor(
    private val repository: AuthRepository
) {
    operator fun invoke(): Flow<Boolean> = repository.isLoggedIn
}
