package ru.qmods.client.domain.usecase

import ru.qmods.client.domain.repository.DeviceRepository
import javax.inject.Inject

class GetDeviceUseCase @Inject constructor(
    private val repository: DeviceRepository
) {
    suspend operator fun invoke() = repository.getDevice()
}

class UnlinkDeviceUseCase @Inject constructor(
    private val repository: DeviceRepository
) {
    suspend operator fun invoke() = repository.unlinkDevice()
}
