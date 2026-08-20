package ru.qmods.client.di

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import ru.qmods.client.data.repository.AuthRepositoryImpl
import ru.qmods.client.data.repository.DeviceRepositoryImpl
import ru.qmods.client.data.repository.NotificationsRepositoryImpl
import ru.qmods.client.data.repository.PaymentsRepositoryImpl
import ru.qmods.client.data.repository.ProfileRepositoryImpl
import ru.qmods.client.data.repository.SubscriptionRepositoryImpl
import ru.qmods.client.domain.repository.AuthRepository
import ru.qmods.client.domain.repository.DeviceRepository
import ru.qmods.client.domain.repository.NotificationsRepository
import ru.qmods.client.domain.repository.PaymentsRepository
import ru.qmods.client.domain.repository.ProfileRepository
import ru.qmods.client.domain.repository.SubscriptionRepository
import ru.qmods.client.util.ConnectivityObserver
import ru.qmods.client.util.NetworkConnectivityObserver
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {

    @Binds
    @Singleton
    abstract fun bindAuthRepository(impl: AuthRepositoryImpl): AuthRepository

    @Binds
    @Singleton
    abstract fun bindProfileRepository(impl: ProfileRepositoryImpl): ProfileRepository

    @Binds
    @Singleton
    abstract fun bindSubscriptionRepository(impl: SubscriptionRepositoryImpl): SubscriptionRepository

    @Binds
    @Singleton
    abstract fun bindDeviceRepository(impl: DeviceRepositoryImpl): DeviceRepository

    @Binds
    @Singleton
    abstract fun bindPaymentsRepository(impl: PaymentsRepositoryImpl): PaymentsRepository

    @Binds
    @Singleton
    abstract fun bindNotificationsRepository(impl: NotificationsRepositoryImpl): NotificationsRepository

    @Binds
    @Singleton
    abstract fun bindConnectivityObserver(impl: NetworkConnectivityObserver): ConnectivityObserver
}
