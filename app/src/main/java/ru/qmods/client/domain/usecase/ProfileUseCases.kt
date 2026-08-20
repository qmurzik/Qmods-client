package ru.qmods.client.domain.usecase

import ru.qmods.client.domain.repository.ProfileRepository
import javax.inject.Inject

class GetProfileUseCase @Inject constructor(
    private val repository: ProfileRepository
) {
    suspend operator fun invoke() = repository.getProfile()
}
