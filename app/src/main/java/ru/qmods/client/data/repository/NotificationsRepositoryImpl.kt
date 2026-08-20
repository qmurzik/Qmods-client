package ru.qmods.client.data.repository

import ru.qmods.client.data.api.QModsApiService
import ru.qmods.client.data.mapper.toDomain
import ru.qmods.client.data.util.safeApiCall
import ru.qmods.client.domain.model.AppNotification
import ru.qmods.client.domain.repository.NotificationsRepository
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.domain.util.Resource
import ru.qmods.client.util.ConnectivityObserver
import javax.inject.Inject

class NotificationsRepositoryImpl @Inject constructor(
    private val api: QModsApiService,
    private val connectivityObserver: ConnectivityObserver
) : NotificationsRepository {

    override suspend fun getNotifications(): Resource<List<AppNotification>> {
        return when (val result = safeApiCall(connectivityObserver) { api.getNotifications() }) {
            is Resource.Success -> {
                val body = result.data
                if (body.success) {
                    Resource.Success(body.notifications.map { it.toDomain() })
                } else {
                    Resource.Error(body.message ?: "Не удалось загрузить уведомления", ErrorType.SERVER)
                }
            }
            is Resource.Error -> Resource.Error(result.message, result.type)
            is Resource.Loading -> Resource.Loading()
        }
    }

    override suspend fun markAsRead(id: String): Resource<Unit> {
        return when (val result = safeApiCall(connectivityObserver) { api.markNotificationRead(id) }) {
            is Resource.Success -> {
                val body = result.data
                if (body.success) {
                    Resource.Success(Unit)
                } else {
                    Resource.Error(body.message ?: "Не удалось обновить уведомление", ErrorType.SERVER)
                }
            }
            is Resource.Error -> Resource.Error(result.message, result.type)
            is Resource.Loading -> Resource.Loading()
        }
    }
}
