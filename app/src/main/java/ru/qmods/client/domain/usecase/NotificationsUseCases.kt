package ru.qmods.client.domain.usecase

import ru.qmods.client.domain.repository.NotificationsRepository
import javax.inject.Inject

class GetNotificationsUseCase @Inject constructor(
    private val repository: NotificationsRepository
) {
    suspend operator fun invoke() = repository.getNotifications()
}

class MarkNotificationReadUseCase @Inject constructor(
    private val repository: NotificationsRepository
) {
    suspend operator fun invoke(id: String) = repository.markAsRead(id)
}
