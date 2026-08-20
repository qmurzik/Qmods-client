package ru.qmods.client.domain.util

/**
 * Wraps the outcome of a repository call for the UI layer.
 * [ErrorType] lets screens react differently to a dead connection vs. an expired
 * session vs. a generic server error without parsing message strings.
 */
sealed class Resource<out T> {
    data class Loading<out T>(val cachedData: T? = null) : Resource<T>()
    data class Success<out T>(val data: T) : Resource<T>()
    data class Error<out T>(
        val message: String,
        val type: ErrorType = ErrorType.UNKNOWN,
        val cachedData: T? = null
    ) : Resource<T>()
}

enum class ErrorType {
    NO_INTERNET,
    SESSION_EXPIRED,
    SERVER,
    UNKNOWN
}
