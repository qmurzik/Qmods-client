package ru.qmods.client.data.mapper

import ru.qmods.client.data.model.DeviceDto
import ru.qmods.client.data.model.NotificationDto
import ru.qmods.client.data.model.PaymentDto
import ru.qmods.client.data.model.PlanDto
import ru.qmods.client.data.model.ProfileResponseDto
import ru.qmods.client.data.model.SubscriptionResponseDto
import ru.qmods.client.domain.model.AppNotification
import ru.qmods.client.domain.model.Device
import ru.qmods.client.domain.model.Payment
import ru.qmods.client.domain.model.PaymentStatus
import ru.qmods.client.domain.model.Plan
import ru.qmods.client.domain.model.Subscription
import ru.qmods.client.domain.model.User

fun ProfileResponseDto.toDomain(): User = User(
    id = id.orEmpty(),
    login = login.orEmpty(),
    email = email,
    registeredAt = registeredAt,
    avatarUrl = avatarUrl
)

fun SubscriptionResponseDto.toDomain(): Subscription = Subscription(
    isActive = active,
    planName = planName,
    expiresAt = expiresAt,
    daysLeft = daysLeft.coerceAtLeast(0)
)

fun PlanDto.toDomain(): Plan = Plan(
    id = id,
    name = name,
    price = price,
    currency = currency,
    durationDays = durationDays,
    isPopular = isPopular
)

fun PaymentDto.toDomain(): Payment = Payment(
    id = id,
    date = date,
    amount = amount,
    currency = currency,
    planName = planName,
    status = when (status?.lowercase()) {
        "success", "paid", "completed", "confirmed" -> PaymentStatus.SUCCESS
        "pending", "processing", "waiting" -> PaymentStatus.PENDING
        "failed", "canceled", "cancelled", "error" -> PaymentStatus.FAILED
        else -> PaymentStatus.UNKNOWN
    }
)

fun DeviceDto.toDomain(): Device = Device(
    deviceId = deviceId,
    model = model.orEmpty(),
    androidVersion = androidVersion.orEmpty(),
    clientVersion = clientVersion.orEmpty(),
    linkedAt = linkedAt,
    lastSeenAt = lastSeenAt
)

fun NotificationDto.toDomain(): AppNotification = AppNotification(
    id = id,
    title = title.orEmpty(),
    message = message,
    date = date.orEmpty(),
    isRead = isRead
)
