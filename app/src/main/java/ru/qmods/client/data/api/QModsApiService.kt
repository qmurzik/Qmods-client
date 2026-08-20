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
import ru.qmods.client.data.model.PlansResponseDto
import ru.qmods.client.data.model.ProfileResponseDto
import ru.qmods.client.data.model.SubscriptionResponseDto

/**
 * Every path below is resolved against the base URL "https://qmods.ru/api/", so e.g.
 * "client_api.php/profile" hits https://qmods.ru/api/client_api.php/profile - i.e. the
 * router is expected to dispatch on PATH_INFO after client_api.php. If the real backend
 * instead routes via a query parameter (client_api.php?action=profile), only the
 * `@GET`/`@POST` path strings here need to change - nothing else in the app depends on it.
 */
interface QModsApiService {

    @POST("client_api.php/login")
    suspend fun login(@Body request: LoginRequestDto): Response<LoginResponseDto>

    @GET("client_api.php/profile")
    suspend fun getProfile(): Response<ProfileResponseDto>

    @GET("client_api.php/subscription")
    suspend fun getSubscription(): Response<SubscriptionResponseDto>

    @GET("client_api.php/subscription/plans")
    suspend fun getSubscriptionPlans(): Response<PlansResponseDto>

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
