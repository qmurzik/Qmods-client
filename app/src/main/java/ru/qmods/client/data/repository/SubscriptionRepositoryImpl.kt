package ru.qmods.client.data.repository

import ru.qmods.client.data.api.QModsApiService
import ru.qmods.client.data.mapper.toDomain
import ru.qmods.client.data.model.RenewSubscriptionRequestDto
import ru.qmods.client.data.util.safeApiCall
import ru.qmods.client.domain.model.PaymentInitiation
import ru.qmods.client.domain.model.Plan
import ru.qmods.client.domain.model.Subscription
import ru.qmods.client.domain.repository.SubscriptionRepository
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.domain.util.Resource
import ru.qmods.client.util.ConnectivityObserver
import javax.inject.Inject

class SubscriptionRepositoryImpl @Inject constructor(
    private val api: QModsApiService,
    private val connectivityObserver: ConnectivityObserver
) : SubscriptionRepository {

    override suspend fun getSubscription(): Resource<Subscription> {
        return when (val result = safeApiCall(connectivityObserver) { api.getSubscription() }) {
            is Resource.Success -> {
                val body = result.data
                if (body.success) {
                    Resource.Success(body.toDomain())
                } else {
                    Resource.Error(body.message ?: "Не удалось загрузить подписку", ErrorType.SERVER)
                }
            }
            is Resource.Error -> Resource.Error(result.message, result.type)
            is Resource.Loading -> Resource.Loading()
        }
    }

    /** subscription/plans returns a bare JSON array - there's no {success,...} envelope to check. */
    override suspend fun getPlans(): Resource<List<Plan>> {
        return when (val result = safeApiCall(connectivityObserver) { api.getSubscriptionPlans() }) {
            is Resource.Success -> Resource.Success(result.data.map { it.toDomain() })
            is Resource.Error -> Resource.Error(result.message, result.type)
            is Resource.Loading -> Resource.Loading()
        }
    }

    override suspend fun renewSubscription(planId: String): Resource<PaymentInitiation> {
        val result = safeApiCall(connectivityObserver) {
            api.renewSubscription(RenewSubscriptionRequestDto(planId = planId))
        }
        return when (result) {
            is Resource.Success -> {
                val body = result.data
                val paymentUrl = body.paymentUrl
                val label = body.label
                if (body.success && !paymentUrl.isNullOrBlank() && !label.isNullOrBlank()) {
                    Resource.Success(PaymentInitiation(paymentUrl = paymentUrl, label = label))
                } else {
                    Resource.Error(body.message ?: "Не удалось создать заказ на оплату", ErrorType.SERVER)
                }
            }
            is Resource.Error -> Resource.Error(result.message, result.type)
            is Resource.Loading -> Resource.Loading()
        }
    }
}
