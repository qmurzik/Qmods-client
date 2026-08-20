package ru.qmods.client.domain.model

enum class PaymentStatus { SUCCESS, PENDING, FAILED, UNKNOWN }

data class Payment(
    val id: String,
    val date: String,
    val amount: Double,
    val currency: String,
    val planName: String?,
    val status: PaymentStatus
)
