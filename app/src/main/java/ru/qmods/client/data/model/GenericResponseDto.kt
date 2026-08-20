package ru.qmods.client.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Shape used by every "action" style endpoint that has no payload of its own. */
@Serializable
data class GenericResponseDto(
    @SerialName("success") val success: Boolean = false,
    @SerialName("message") val message: String? = null
)
