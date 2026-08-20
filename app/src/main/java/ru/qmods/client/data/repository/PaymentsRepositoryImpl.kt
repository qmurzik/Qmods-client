package ru.qmods.client.data.repository

import ru.qmods.client.data.api.QModsApiService
import ru.qmods.client.data.mapper.toDomain
import ru.qmods.client.data.util.safeApiCall
import ru.qmods.client.domain.model.Payment
import ru.qmods.client.domain.repository.PaymentsRepository
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.domain.util.Resource
import ru.qmods.client.util.ConnectivityObserver
import javax.inject.Inject

class PaymentsRepositoryImpl @Inject constructor(
    private val api: QModsApiService,
    private val connectivityObserver: ConnectivityObserver
) : PaymentsRepository {

    override suspend fun getPayments(): Resource<List<Payment>> {
        return when (val result = safeApiCall(connectivityObserver) { api.getPayments() }) {
            is Resource.Success -> {
                val body = result.data
                if (body.success) {
                    Resource.Success(body.payments.map { it.toDomain() })
                } else {
                    Resource.Error(body.message ?: "Не удалось загрузить платежи", ErrorType.SERVER)
                }
            }
            is Resource.Error -> Resource.Error(result.message, result.type)
            is Resource.Loading -> Resource.Loading()
        }
    }
}
