package ru.qmods.client.domain.model

data class Subscription(
    val isActive: Boolean,
    val planName: String?,
    val expiresAt: String?,
    val daysLeft: Int
)
