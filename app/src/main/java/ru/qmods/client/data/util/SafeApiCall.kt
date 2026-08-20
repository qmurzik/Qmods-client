package ru.qmods.client.data.util

import retrofit2.Response
import ru.qmods.client.domain.util.ErrorType
import ru.qmods.client.domain.util.Resource
import ru.qmods.client.util.ConnectivityObserver
import java.io.IOException
import java.net.HttpURLConnection

/**
 * Transport-level wrapper shared by every repository: turns connectivity issues, non-2xx HTTP
 * codes and thrown exceptions into a [Resource.Error] with the right [ErrorType], and hands
 * back the parsed body otherwise. Business-level failure (HTTP 200 with `"success": false` in
 * the body) is intentionally left to the caller, since only it knows how to read that body.
 */
suspend fun <T> safeApiCall(
    connectivityObserver: ConnectivityObserver,
    apiCall: suspend () -> Response<T>
): Resource<T> {
    if (!connectivityObserver.isCurrentlyConnected()) {
        return Resource.Error("Нет подключения к интернету", ErrorType.NO_INTERNET)
    }

    return try {
        val response = apiCall()
        val body = response.body()

        when {
            response.code() == HttpURLConnection.HTTP_UNAUTHORIZED ->
                Resource.Error("Сессия истекла, войдите снова", ErrorType.SESSION_EXPIRED)

            response.isSuccessful && body != null -> Resource.Success(body)

            response.isSuccessful -> Resource.Error("Пустой ответ сервера", ErrorType.SERVER)

            else -> Resource.Error("Ошибка сервера (${response.code()})", ErrorType.SERVER)
        }
    } catch (e: IOException) {
        Resource.Error("Нет подключения к интернету", ErrorType.NO_INTERNET)
    } catch (e: Exception) {
        Resource.Error(e.message ?: "Что-то пошло не так. Попробуйте ещё раз", ErrorType.UNKNOWN)
    }
}
