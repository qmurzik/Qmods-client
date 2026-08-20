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
    @SerialName("device_id") val deviceId: String,
    @SerialName("model") val model: String? = null,
    @SerialName("android_version") val androidVersion: String? = null,
    @SerialName("client_version") val clientVersion: String? = null,
    @SerialName("linked_at") val linkedAt: String? = null,
    @SerialName("last_seen_at") val lastSeenAt: String? = null
)
