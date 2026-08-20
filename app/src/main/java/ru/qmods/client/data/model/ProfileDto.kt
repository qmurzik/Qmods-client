package ru.qmods.client.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ProfileResponseDto(
    @SerialName("success") val success: Boolean = false,
    @SerialName("message") val message: String? = null,
    @SerialName("id") val id: String? = null,
    @SerialName("login") val login: String? = null,
    @SerialName("email") val email: String? = null,
    @SerialName("registered_at") val registeredAt: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null
)
