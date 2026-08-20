package ru.qmods.client.domain.repository

import ru.qmods.client.domain.model.Device
import ru.qmods.client.domain.util.Resource

interface DeviceRepository {
    suspend fun getDevice(): Resource<Device?>
    suspend fun unlinkDevice(): Resource<Unit>
}
