package ru.qmods.client.domain.model

data class User(
    val id: String,
    val login: String,
    val displayName: String?,
    val registeredAt: String?,
    val avatarUrl: String?
)
