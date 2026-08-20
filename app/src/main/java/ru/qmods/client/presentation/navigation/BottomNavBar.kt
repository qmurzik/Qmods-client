package ru.qmods.client.presentation.navigation

import androidx.compose.foundation.layout.height
import androidx.compose.ui.Modifier
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material.icons.outlined.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavHostController
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.compose.ui.unit.dp
import ru.qmods.client.R
import ru.qmods.client.presentation.theme.AccentVioletStart
import ru.qmods.client.presentation.theme.BackgroundElevated
import ru.qmods.client.presentation.theme.TextTertiary

private data class BottomNavItem(
    val screen: Screen,
    val labelRes: Int,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector
)

private val bottomNavItems = listOf(
    BottomNavItem(Screen.Home, R.string.nav_home, Icons.Filled.Home, Icons.Outlined.Home),
    BottomNavItem(Screen.Subscription, R.string.nav_subscription, Icons.Filled.WorkspacePremium, Icons.Outlined.WorkspacePremium),
    BottomNavItem(Screen.Device, R.string.nav_device, Icons.Filled.PhoneAndroid, Icons.Outlined.PhoneAndroid),
    BottomNavItem(Screen.Payments, R.string.nav_payments, Icons.Filled.CreditCard, Icons.Outlined.CreditCard),
    BottomNavItem(Screen.Profile, R.string.nav_profile, Icons.Filled.Person, Icons.Outlined.Person)
)

@Composable
fun QModsBottomNavBar(navController: NavHostController) {
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    NavigationBar(
        containerColor = BackgroundElevated,
        tonalElevation = 0.dp,
        modifier = Modifier.height(72.dp)
    ) {
        bottomNavItems.forEach { item ->
            val selected = currentDestination?.hierarchy?.any { it.route == item.screen.route } == true

            NavigationBarItem(
                selected = selected,
                onClick = {
                    navController.navigate(item.screen.route) {
                        // Anchor on Home (the graph's *effective* home once past auth), not
                        // the NavHost's literal startDestination (Splash) - Splash is popped
                        // with inclusive=true right after first launch, so popUpTo-ing to its
                        // id later matches nothing in the back stack. That silently broke the
                        // save/restore-state contract below: each tab switch was landing on a
                        // fresh back stack entry instead of the saved one, recreating every
                        // screen's ViewModel (and re-firing its network calls) on every tap.
                        popUpTo(Screen.Home.route) {
                            saveState = true
                        }
                        launchSingleTop = true
                        restoreState = true
                    }
                },
                icon = {
                    Icon(
                        imageVector = if (selected) item.selectedIcon else item.unselectedIcon,
                        contentDescription = stringResource(id = item.labelRes)
                    )
                },
                label = {
                    Text(
                        text = stringResource(id = item.labelRes),
                        style = MaterialTheme.typography.labelSmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = AccentVioletStart,
                    selectedTextColor = AccentVioletStart,
                    unselectedIconColor = TextTertiary,
                    unselectedTextColor = TextTertiary,
                    indicatorColor = BackgroundElevated
                )
            )
        }
    }
}
