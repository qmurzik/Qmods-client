package ru.qmods.client.domain.usecase

import ru.qmods.client.domain.repository.PaymentsRepository
import javax.inject.Inject

class GetPaymentsUseCase @Inject constructor(
    private val repository: PaymentsRepository
) {
    suspend operator fun invoke() = repository.getPayments()
}
