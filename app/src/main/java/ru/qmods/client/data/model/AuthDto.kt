package ru.qmods.client.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class LoginRequestDto(
    @SerialName("login") val login: String,
    @SerialName("password") val password: String,
    @SerialName("device_id") val deviceId: String,
    @SerialName("device_model") val deviceModel: String,
    @SerialName("android_version") val androidVersion: String,
    @SerialName("client_version") val clientVersion: String
)

@Serializable
data class LoginResponseDto(
    @SerialName("success") val success: Boolean = false,
    @SerialName("session_token") val sessionToken: String? = null,
    @SerialName("message") val message: String? = null
)
