package ru.qmods.client.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class PaymentsResponseDto(
    @SerialName("success") val success: Boolean = false,
    @SerialName("message") val message: String? = null,
    @SerialName("payments") val payments: List<PaymentDto> = emptyList()
)

@Serializable
data class PaymentDto(
    @SerialName("id") val id: String = "",
    @SerialName("date") val date: Long = 0,
    @SerialName("amount") val amount: Int = 0,
    @SerialName("plan") val plan: String? = null,
    @SerialName("status") val status: String? = null
)
