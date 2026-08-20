package ru.qmods.client.presentation.components

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/** Standard pull-to-refresh container used by every list/detail screen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RefreshableScreen(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    PullToRefreshBox(
        isRefreshing = isRefreshing,
        onRefresh = onRefresh,
        modifier = modifier.fillMaxSize(),
        content = { content() }
    )
}
