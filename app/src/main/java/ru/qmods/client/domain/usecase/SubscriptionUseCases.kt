package ru.qmods.client.domain.usecase

import ru.qmods.client.domain.repository.SubscriptionRepository
import javax.inject.Inject

class GetSubscriptionUseCase @Inject constructor(
    private val repository: SubscriptionRepository
) {
    suspend operator fun invoke() = repository.getSubscription()
}

class GetPlansUseCase @Inject constructor(
    private val repository: SubscriptionRepository
) {
    suspend operator fun invoke() = repository.getPlans()
}
