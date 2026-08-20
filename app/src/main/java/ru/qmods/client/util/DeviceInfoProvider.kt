package ru.qmods.client.util

import android.os.Build
import ru.qmods.client.BuildConfig
import ru.qmods.client.data.local.SessionManager
import ru.qmods.client.domain.model.DeviceInfo
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DeviceInfoProvider @Inject constructor(
    private val sessionManager: SessionManager
) {
    suspend fun current(): DeviceInfo = DeviceInfo(
        deviceId = sessionManager.getOrCreateDeviceId(),
        deviceModel = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
        androidVersion = Build.VERSION.RELEASE ?: Build.VERSION.SDK_INT.toString(),
        clientVersion = BuildConfig.CLIENT_VERSION
    )
}
