package ru.qmods.client.domain.repository

import ru.qmods.client.domain.model.PaymentInitiation
import ru.qmods.client.domain.model.Plan
import ru.qmods.client.domain.model.Subscription
import ru.qmods.client.domain.util.Resource

interface SubscriptionRepository {
    suspend fun getSubscription(): Resource<Subscription>
    suspend fun getPlans(): Resource<List<Plan>>
    suspend fun renewSubscription(planId: String): Resource<PaymentInitiation>
}
