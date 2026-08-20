package ru.qmods.client.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SubscriptionResponseDto(
    @SerialName("success") val success: Boolean = false,
    @SerialName("message") val message: String? = null,
    @SerialName("status") val status: String? = null,
    @SerialName("plan") val plan: String? = null,
    @SerialName("plan_title") val planTitle: String? = null,
    @SerialName("expires_at") val expiresAt: Long = 0,
    @SerialName("days_left") val daysLeft: Int = 0
)

/**
 * GET subscription/plans returns a bare JSON array (no {success, plans:[...]} wrapper),
 * so this is deserialized directly as List<PlanDto> - see QModsApiService.
 */
@Serializable
data class PlanDto(
    @SerialName("id") val id: String = "",
    @SerialName("title") val title: String = "",
    @SerialName("price_rub") val priceRub: Int = 0,
    @SerialName("duration_days") val durationDays: Int = 0,
    @SerialName("recommended") val recommended: Boolean = false
)

@Serializable
data class RenewSubscriptionRequestDto(
    @SerialName("plan_id") val planId: String
)

@Serializable
data class RenewSubscriptionResponseDto(
    @SerialName("success") val success: Boolean = false,
    @SerialName("message") val message: String? = null,
    @SerialName("payment_url") val paymentUrl: String? = null,
    @SerialName("label") val label: String? = null
)
