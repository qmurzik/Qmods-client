package ru.qmods.client.domain.model

enum class PaymentStatus { SUCCESS, PENDING, FAILED, UNKNOWN }

/** amountRub: whole rubles, no currency field is sent by the API. */
data class Payment(
    val id: String,
    val date: String,
    val amountRub: Int,
    val planName: String?,
    val status: PaymentStatus
)
