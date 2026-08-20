package ru.qmods.client.data.repository

import ru.qmods.client.data.api.QModsApiService
import ru.qmods.client.data.mapper.toDomain
import ru.qmods.client.data.util.safeApiCall
import ru.qmods.client.domain.model.Device
import ru.qmods.client.domain.repository.DeviceRepository
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.domain.util.Resource
import ru.qmods.client.util.ConnectivityObserver
import javax.inject.Inject

class DeviceRepositoryImpl @Inject constructor(
    private val api: QModsApiService,
    private val connectivityObserver: ConnectivityObserver
) : DeviceRepository {

    override suspend fun getDevice(): Resource<Device?> {
        return when (val result = safeApiCall(connectivityObserver) { api.getDevice() }) {
            is Resource.Success -> {
                val body = result.data
                if (body.success) {
                    Resource.Success(body.device?.toDomain())
                } else {
                    Resource.Error(body.message ?: "Не удалось загрузить устройство", ErrorType.SERVER)
                }
            }
            is Resource.Error -> Resource.Error(result.message, result.type)
            is Resource.Loading -> Resource.Loading()
        }
    }

    override suspend fun unlinkDevice(): Resource<Unit> {
        return when (val result = safeApiCall(connectivityObserver) { api.unlinkDevice() }) {
            is Resource.Success -> {
                val body = result.data
                if (body.success) {
                    Resource.Success(Unit)
                } else {
                    Resource.Error(body.message ?: "Не удалось отвязать устройство", ErrorType.SERVER)
                }
            }
            is Resource.Error -> Resource.Error(result.message, result.type)
            is Resource.Loading -> Resource.Loading()
        }
    }
}
