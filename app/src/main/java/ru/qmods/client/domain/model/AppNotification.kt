package ru.qmods.client.domain.model

data class AppNotification(
    val id: String,
    val title: String,
    val message: String,
    val date: String,
    val isRead: Boolean
)
