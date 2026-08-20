package ru.qmods.client.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SubscriptionResponseDto(
    @SerialName("success") val success: Boolean = false,
    @SerialName("message") val message: String? = null,
    @SerialName("active") val active: Boolean = false,
    @SerialName("plan_name") val planName: String? = null,
    @SerialName("expires_at") val expiresAt: String? = null,
    @SerialName("days_left") val daysLeft: Int = 0
)

@Serializable
data class PlansResponseDto(
    @SerialName("success") val success: Boolean = false,
    @SerialName("message") val message: String? = null,
    @SerialName("plans") val plans: List<PlanDto> = emptyList()
)

@Serializable
data class PlanDto(
    @SerialName("id") val id: String = "",
    @SerialName("name") val name: String = "",
    @SerialName("price") val price: Double = 0.0,
    @SerialName("currency") val currency: String = "RUB",
    @SerialName("duration_days") val durationDays: Int = 0,
    @SerialName("is_popular") val isPopular: Boolean = false
)
