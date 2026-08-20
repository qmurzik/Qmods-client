package ru.qmods.client.domain.model

data class Device(
    val deviceId: String,
    val model: String,
    val androidVersion: String,
    val clientVersion: String,
    val linkedAt: String?,
    val lastSeenAt: String?
)
