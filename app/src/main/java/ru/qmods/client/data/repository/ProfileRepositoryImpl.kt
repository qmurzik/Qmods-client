package ru.qmods.client.data.repository

import ru.qmods.client.data.api.QModsApiService
import ru.qmods.client.data.mapper.toDomain
import ru.qmods.client.data.util.safeApiCall
import ru.qmods.client.domain.model.User
import ru.qmods.client.domain.repository.ProfileRepository
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.domain.util.Resource
import ru.qmods.client.util.ConnectivityObserver
import javax.inject.Inject

class ProfileRepositoryImpl @Inject constructor(
    private val api: QModsApiService,
    private val connectivityObserver: ConnectivityObserver
) : ProfileRepository {

    override suspend fun getProfile(): Resource<User> {
        return when (val result = safeApiCall(connectivityObserver) { api.getProfile() }) {
            is Resource.Success -> {
                val body = result.data
                if (body.success) {
                    Resource.Success(body.toDomain())
                } else {
                    Resource.Error(body.message ?: "Не удалось загрузить профиль", ErrorType.SERVER)
                }
            }
            is Resource.Error -> Resource.Error(result.message, result.type)
            is Resource.Loading -> Resource.Loading()
        }
    }
}
