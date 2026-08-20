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
    @SerialName("id") val id: String,
    @SerialName("date") val date: String,
    @SerialName("amount") val amount: Double = 0.0,
    @SerialName("currency") val currency: String = "RUB",
    @SerialName("plan_name") val planName: String? = null,
    @SerialName("status") val status: String? = null
)
