package ru.qmods.client.data.mapper

import ru.qmods.client.data.model.DeviceDto
import ru.qmods.client.data.model.NotificationDto
import ru.qmods.client.data.model.PaymentDto
import ru.qmods.client.data.model.PlanDto
import ru.qmods.client.data.model.SubscriptionResponseDto
import ru.qmods.client.data.model.UserDto
import ru.qmods.client.domain.model.AppNotification
import ru.qmods.client.domain.model.Device
import ru.qmods.client.domain.model.Payment
import ru.qmods.client.domain.model.PaymentStatus
import ru.qmods.client.domain.model.Plan
import ru.qmods.client.domain.model.Subscription
import ru.qmods.client.domain.model.User

fun UserDto.toDomain(): User = User(
    id = id,
    login = login,
    displayName = displayName,
    registeredAt = epochSecondsToDateString(createdAt),
    avatarUrl = avatarUrl
)

fun SubscriptionResponseDto.toDomain(): Subscription = Subscription(
    isActive = status == "active",
    planName = planTitle?.takeIf { it.isNotBlank() } ?: plan,
    expiresAt = epochSecondsToDateString(expiresAt),
    daysLeft = daysLeft.coerceAtLeast(0)
)

fun PlanDto.toDomain(): Plan = Plan(
    id = id,
    name = title,
    priceRub = priceRub,
    durationDays = durationDays,
    isPopular = recommended
)

fun PaymentDto.toDomain(): Payment = Payment(
    id = id,
    date = epochSecondsToDateString(date).orEmpty(),
    amountRub = amount,
    planName = plan,
    status = when (status?.lowercase()) {
        "success", "paid", "completed", "confirmed" -> PaymentStatus.SUCCESS
        "pending", "processing", "waiting" -> PaymentStatus.PENDING
        "failed", "canceled", "cancelled", "error" -> PaymentStatus.FAILED
        else -> PaymentStatus.UNKNOWN
    }
)

fun DeviceDto.toDomain(): Device = Device(
    deviceId = id,
    model = model.orEmpty(),
    androidVersion = androidVersion.orEmpty(),
    clientVersion = clientVersion.orEmpty(),
    linkedAt = epochSecondsToDateString(linkedAt),
    lastSeenAt = epochSecondsToDateString(lastSeen)
)

fun NotificationDto.toDomain(): AppNotification = AppNotification(
    id = id,
    title = title.orEmpty(),
    message = body,
    date = epochSecondsToDateString(createdAt).orEmpty(),
    isRead = read
)
