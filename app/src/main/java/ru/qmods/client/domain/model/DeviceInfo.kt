package ru.qmods.client.domain.model

data class DeviceInfo(
    val deviceId: String,
    val deviceModel: String,
    val androidVersion: String,
    val clientVersion: String
)
