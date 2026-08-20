package ru.qmods.client.domain.repository

import ru.qmods.client.domain.model.AppNotification
import ru.qmods.client.domain.util.Resource

interface NotificationsRepository {
    suspend fun getNotifications(): Resource<List<AppNotification>>
    suspend fun markAsRead(id: String): Resource<Unit>
}
