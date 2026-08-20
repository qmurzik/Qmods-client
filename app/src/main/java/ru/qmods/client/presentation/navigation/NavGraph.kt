package ru.qmods.client.presentation.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import ru.qmods.client.presentation.screens.device.DeviceScreen
import ru.qmods.client.presentation.screens.home.HomeScreen
import ru.qmods.client.presentation.screens.login.LoginScreen
import ru.qmods.client.presentation.screens.notifications.NotificationsScreen
import ru.qmods.client.presentation.screens.payments.PaymentsScreen
import ru.qmods.client.presentation.screens.profile.ProfileScreen
import ru.qmods.client.presentation.screens.splash.SplashScreen
import ru.qmods.client.presentation.screens.subscription.PlansScreen
import ru.qmods.client.presentation.screens.subscription.SubscriptionScreen

@Composable
fun QModsNavGraph(navController: NavHostController = rememberNavController()) {
    val sessionViewModel: SessionViewModel = hiltViewModel()
    val isLoggedIn by sessionViewModel.isLoggedIn.collectAsStateWithLifecycle()

    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route

    LaunchedEffect(isLoggedIn, currentRoute) {
        val isOnAuthenticatedScreen = currentRoute != null &&
            currentRoute != Screen.Splash.route &&
            currentRoute != Screen.Login.route

        if (isLoggedIn == false && isOnAuthenticatedScreen) {
            navController.navigate(Screen.Login.route) {
                popUpTo(0) { inclusive = true }
                launchSingleTop = true
            }
        }
    }

    val showBottomBar = Screen.bottomBarScreens.any { it.route == currentRoute }

    Scaffold(
        bottomBar = { if (showBottomBar) QModsBottomNavBar(navController) }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Splash.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(Screen.Splash.route) {
                SplashScreen(
                    onNavigateToHome = {
                        navController.navigate(Screen.Home.route) {
                            popUpTo(Screen.Splash.route) { inclusive = true }
                        }
                    },
                    onNavigateToLogin = {
                        navController.navigate(Screen.Login.route) {
                            popUpTo(Screen.Splash.route) { inclusive = true }
                        }
                    }
                )
            }

            composable(Screen.Login.route) {
                LoginScreen(
                    onLoginSuccess = {
                        navController.navigate(Screen.Home.route) {
                            popUpTo(Screen.Login.route) { inclusive = true }
                        }
                    }
                )
            }

            composable(Screen.Home.route) {
                HomeScreen(
                    onNavigateToNotifications = { navController.navigate(Screen.Notifications.route) },
                    onNavigateToSubscription = {
                        navController.navigate(Screen.Subscription.route) {
                            popUpTo(Screen.Home.route)
                            launchSingleTop = true
                        }
                    },
                    onNavigateToDevice = {
                        navController.navigate(Screen.Device.route) {
                            popUpTo(Screen.Home.route)
                            launchSingleTop = true
                        }
                    },
                    onNavigateToPayments = {
                        navController.navigate(Screen.Payments.route) {
                            popUpTo(Screen.Home.route)
                            launchSingleTop = true
                        }
                    }
                )
            }

            composable(Screen.Subscription.route) {
                SubscriptionScreen(onNavigateToPlans = { navController.navigate(Screen.Plans.route) })
            }

            composable(Screen.Plans.route) {
                PlansScreen(onBack = { navController.popBackStack() })
            }

            composable(Screen.Device.route) {
                DeviceScreen()
            }

            composable(Screen.Payments.route) {
                PaymentsScreen()
            }

            composable(Screen.Profile.route) {
                ProfileScreen()
            }

            composable(Screen.Notifications.route) {
                NotificationsScreen(onBack = { navController.popBackStack() })
            }
        }
    }
}
