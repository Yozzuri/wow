package com.toastp.langlearn

import android.service.notification.NotificationListenerService

/**
 * Exists only to grant this app access to active MediaSessions once the user
 * enables notification access in system settings.
 */
class MediaNotificationListenerService : NotificationListenerService()
