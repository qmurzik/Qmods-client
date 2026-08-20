package ru.qmods.client.data.mapper

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * The PHP API sends every date as a Unix timestamp in seconds (`time()`), not a formatted
 * string. Converts that to a display-ready "dd.MM.yyyy" string, or null for a missing/zero
 * timestamp (the API uses 0 as "not set", e.g. a subscription that never had an expiry).
 */
private val DATE_FORMATTER: DateTimeFormatter = DateTimeFormatter.ofPattern("dd.MM.yyyy")

fun epochSecondsToDateString(epochSeconds: Long?): String? {
    if (epochSeconds == null || epochSeconds <= 0) return null
    return Instant.ofEpochSecond(epochSeconds)
        .atZone(ZoneId.systemDefault())
        .format(DATE_FORMATTER)
}
