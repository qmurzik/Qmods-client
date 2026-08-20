package ru.qmods.client.data.api

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import okhttp3.Interceptor
import okhttp3.Response
import ru.qmods.client.data.local.SessionManager
import ru.qmods.client.di.ApplicationScope
import ru.qmods.client.util.Constants
import java.net.HttpURLConnection
import javax.inject.Inject

/**
 * Attaches "Authorization: Bearer <token>" to every request except login, and reacts to a
 * 401 response by wiping the local session so the UI falls back to the login screen. This is
 * a plain [Interceptor] rather than an [okhttp3.Authenticator] because the API has no token
 * refresh endpoint - a 401 always means "log in again", never "retry with a new token".
 */
class AuthInterceptor @Inject constructor(
    private val sessionManager: SessionManager,
    @ApplicationScope private val applicationScope: CoroutineScope
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        val isLoginRequest = original.url.encodedPath.endsWith("/login")

        val request = if (isLoginRequest) {
            original
        } else {
            val token = sessionManager.currentTokenOrNull()
            if (token.isNullOrBlank()) {
                original
            } else {
                original.newBuilder()
                    .header(Constants.HEADER_AUTHORIZATION, Constants.BEARER_PREFIX + token)
                    .build()
            }
        }

        val response = chain.proceed(request)

        if (!isLoginRequest && response.code == HttpURLConnection.HTTP_UNAUTHORIZED) {
            applicationScope.launch { sessionManager.clearSession() }
        }

        return response
    }
}
