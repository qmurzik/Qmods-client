package ru.qmods.client.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class DeviceResponseDto(
    @SerialName("success") val success: Boolean = false,
    @SerialName("message") val message: String? = null,
    @SerialName("device") val device: DeviceDto? = null
)

@Serializable
data class DeviceDto(
    @SerialName("id") val id: String = "",
    @SerialName("model") val model: String? = null,
    @SerialName("android_version") val androidVersion: String? = null,
    @SerialName("client_version") val clientVersion: String? = null,
    @SerialName("linked_at") val linkedAt: Long = 0,
    @SerialName("last_seen") val lastSeen: Long = 0
)
