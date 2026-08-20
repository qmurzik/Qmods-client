package ru.qmods.client.domain.repository

import ru.qmods.client.domain.model.User
import ru.qmods.client.domain.util.Resource

interface ProfileRepository {
    suspend fun getProfile(): Resource<User>
}
