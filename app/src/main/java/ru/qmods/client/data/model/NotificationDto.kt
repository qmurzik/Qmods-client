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
    @SerialName("body") val body: String = "",
    @SerialName("created_at") val createdAt: Long = 0,
    @SerialName("read") val read: Boolean = false,
    @SerialName("type") val type: String? = null
)
