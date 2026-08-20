package ru.qmods.client.domain.model

/** priceRub: the API only ever prices plans in whole rubles, no currency field is sent. */
data class Plan(
    val id: String,
    val name: String,
    val priceRub: Int,
    val durationDays: Int,
    val isPopular: Boolean = false
)
