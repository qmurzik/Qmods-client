package ru.qmods.client.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class NotificationsResponseDto(
    @SerialName("success") val success: Boolean = false,
    @SerialName("message") val message: String? = null,
    @SerialName("notifications") val notifications: List<NotificationDto> = emptyList()
)

@Serializable
data class NotificationDto(
    @SerialName("id") val id: String = "",
    @SerialName("title") val title: String? = null,
    @SerialName("message") val message: String = "",
    @SerialName("date") val date: String? = null,
    @SerialName("is_read") val isRead: Boolean = false
)
