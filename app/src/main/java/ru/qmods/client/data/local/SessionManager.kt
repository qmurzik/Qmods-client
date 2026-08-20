package ru.qmods.client.data.local

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import ru.qmods.client.di.ApplicationScope
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SessionManager @Inject constructor(
    private val dataStore: DataStore<Preferences>,
    @ApplicationScope private val applicationScope: CoroutineScope
) {
    private object Keys {
        val SESSION_TOKEN = stringPreferencesKey("session_token")
        val DEVICE_ID = stringPreferencesKey("device_id")
    }

    val sessionTokenFlow: Flow<String?> = dataStore.data.map { it[Keys.SESSION_TOKEN] }

    val isLoggedIn: Flow<Boolean> = sessionTokenFlow.map { !it.isNullOrBlank() }

    /**
     * In-memory mirror of the persisted token so the OkHttp interceptor - which runs
     * synchronously on a background thread but must not block on DataStore I/O - can attach
     * the Authorization header without a suspend call.
     */
    private val cachedToken: StateFlow<String?> =
        sessionTokenFlow.stateIn(applicationScope, SharingStarted.Eagerly, null)

    fun currentTokenOrNull(): String? = cachedToken.value

    suspend fun saveSessionToken(token: String) {
        dataStore.edit { it[Keys.SESSION_TOKEN] = token }
    }

    suspend fun clearSession() {
        dataStore.edit { it.remove(Keys.SESSION_TOKEN) }
    }

    suspend fun getOrCreateDeviceId(): String {
        val existing = dataStore.data.first()[Keys.DEVICE_ID]
        if (!existing.isNullOrBlank()) return existing

        val newId = UUID.randomUUID().toString()
        dataStore.edit { it[Keys.DEVICE_ID] = newId }
        return newId
    }
}
