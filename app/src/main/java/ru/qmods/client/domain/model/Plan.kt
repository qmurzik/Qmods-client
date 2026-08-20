package ru.qmods.client.domain.model

data class Plan(
    val id: String,
    val name: String,
    val price: Double,
    val currency: String,
    val durationDays: Int,
    val isPopular: Boolean = false
)
