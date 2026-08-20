package ru.qmods.client.domain.model

/** Result of starting a plan purchase: where to send the user to pay, and the order label. */
data class PaymentInitiation(
    val paymentUrl: String,
    val label: String
)
