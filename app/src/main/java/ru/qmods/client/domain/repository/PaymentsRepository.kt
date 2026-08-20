package ru.qmods.client.domain.repository

import ru.qmods.client.domain.model.Payment
import ru.qmods.client.domain.util.Resource

interface PaymentsRepository {
    suspend fun getPayments(): Resource<List<Payment>>
}
