package ru.qmods.client.data.api

import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import ru.qmods.client.data.model.DeviceResponseDto
import ru.qmods.client.data.model.GenericResponseDto
import ru.qmods.client.data.model.LoginRequestDto
import ru.qmods.client.data.model.LoginResponseDto
import ru.qmods.client.data.model.NotificationsResponseDto
import ru.qmods.client.data.model.PaymentsResponseDto
import ru.qmods.client.data.model.PlanDto
import ru.qmods.client.data.model.ProfileResponseDto
import ru.qmods.client.data.model.RenewSubscriptionRequestDto
import ru.qmods.client.data.model.RenewSubscriptionResponseDto
import ru.qmods.client.data.model.SubscriptionResponseDto

/**
 * Every path below is resolved against BuildConfig.API_BASE_URL ("https://qmods.ru/mod/api/"),
 * e.g. "client_api.php/profile" hits .../mod/api/client_api.php/profile. client_api.php's own
 * router strips everything up to and including "/api/client_api.php/" via regex, so it doesn't
 * care what comes before "/api/" - see client_api.php line ~21.
 *
 * NOTE: client_api.php has no `case 'device/unlink':` route at all (verified against the real
 * source) - unlinkDevice() below will 404 until that's added server-side. The app handles that
 * as a normal server error rather than crashing, but the button won't actually unlink anything
 * until the endpoint exists.
 */
interface QModsApiService {

    @POST("client_api.php/login")
    suspend fun login(@Body request: LoginRequestDto): Response<LoginResponseDto>

    @POST("client_api.php/logout")
    suspend fun logout(): Response<GenericResponseDto>

    @GET("client_api.php/profile")
    suspend fun getProfile(): Response<ProfileResponseDto>

    @GET("client_api.php/subscription")
    suspend fun getSubscription(): Response<SubscriptionResponseDto>

    /** Bare JSON array response - no {success, plans:[...]} wrapper. */
    @GET("client_api.php/subscription/plans")
    suspend fun getSubscriptionPlans(): Response<List<PlanDto>>

    /** Creates a pending order and returns a YooMoney quickpay URL to open in a browser. */
    @POST("client_api.php/subscription/renew")
    suspend fun renewSubscription(@Body request: RenewSubscriptionRequestDto): Response<RenewSubscriptionResponseDto>

    @GET("client_api.php/payments")
    suspend fun getPayments(): Response<PaymentsResponseDto>

    @GET("client_api.php/device")
    suspend fun getDevice(): Response<DeviceResponseDto>

    @POST("client_api.php/device/unlink")
    suspend fun unlinkDevice(): Response<GenericResponseDto>

    @GET("client_api.php/notifications")
    suspend fun getNotifications(): Response<NotificationsResponseDto>

    @POST("client_api.php/notifications/{id}/read")
    suspend fun markNotificationRead(@Path("id") id: String): Response<GenericResponseDto>
}
