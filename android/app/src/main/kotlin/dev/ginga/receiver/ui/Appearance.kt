package dev.ginga.receiver.ui

import android.app.Activity
import dev.ginga.receiver.R

/**
 * The app's appearance (design/ginga-design/HANDOFF.md, "Temas"): Sistema, Claro, Escuro or
 * Black espacial. Stored in [dev.ginga.receiver.settings.ReceiverSettings.appearance] as
 * [storageValue]; applied with [apply] before an activity inflates its views, and changed at
 * runtime with `recreate()`.
 */
enum class Appearance(val storageValue: String) {
    SYSTEM("system"),
    LIGHT("light"),
    DARK("dark"),
    SPACE("space"),
    ;

    /** The theme that implements it. SYSTEM follows the system's dark mode (values-night). */
    val themeRes: Int
        get() = when (this) {
            SYSTEM -> R.style.Theme_Ginga_System
            LIGHT -> R.style.Theme_Ginga_Light
            DARK -> R.style.Theme_Ginga_Dark
            SPACE -> R.style.Theme_Ginga_Space
        }

    /** Its name in the Appearance picker. */
    val labelRes: Int
        get() = when (this) {
            SYSTEM -> R.string.appearance_system
            LIGHT -> R.string.appearance_light
            DARK -> R.string.appearance_dark
            SPACE -> R.string.appearance_space
        }

    /** Black espacial: the stream's waiting sky is #000 instead of cosmos. */
    val pureBlack: Boolean get() = this == SPACE

    fun apply(activity: Activity) = activity.setTheme(themeRes)

    companion object {
        /** Unknown or missing values fall back to [SYSTEM]. */
        fun fromStorage(value: String?): Appearance = entries.firstOrNull { it.storageValue == value } ?: SYSTEM
    }
}
