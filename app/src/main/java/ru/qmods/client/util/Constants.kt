package ru.qmods.client.util

object Constants {
    const val HEADER_AUTHORIZATION = "Authorization"
    const val BEARER_PREFIX = "Bearer "

    /**
     * SHA-256 SPKI certificate pins for qmods.ru, e.g. "sha256/AAAA...=".
     * Left empty by default: an empty pin list means OkHttp's CertificatePinner is not attached
     * at all, so the app relies on standard system trust-anchor validation (see
     * network_security_config.xml). Fill this in with the real pins (leaf + backup) before a
     * release build to enable certificate pinning - see di/NetworkModule.kt.
     */
    val CERTIFICATE_PINS: List<String> = emptyList()
    const val CERTIFICATE_PIN_HOST = "qmods.ru"
}
