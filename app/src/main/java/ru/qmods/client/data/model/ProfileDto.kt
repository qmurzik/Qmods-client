package ru.qmods.client.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ProfileResponseDto(
    @SerialName("success") val success: Boolean = false,
    @SerialName("message") val message: String? = null,
    @SerialName("user") val user: UserDto? = null
)

@Serializable
data class UserDto(
    @SerialName("id") val id: String = "",
    @SerialName("login") val login: String = "",
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("created_at") val createdAt: Long = 0
)
