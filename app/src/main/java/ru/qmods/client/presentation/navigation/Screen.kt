package ru.qmods.client.presentation.navigation

sealed class Screen(val route: String) {
    data object Splash : Screen("splash")
    data object Login : Screen("login")

    data object Home : Screen("home")
    data object Subscription : Screen("subscription")
    data object Device : Screen("device")
    data object Payments : Screen("payments")
    data object Profile : Screen("profile")

    data object Plans : Screen("plans")
    data object Notifications : Screen("notifications")

    companion object {
        val bottomBarScreens = listOf(Home, Subscription, Device, Payments, Profile)
    }
}
