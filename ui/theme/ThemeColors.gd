extends RefCounted
class_name ThemeColors

# Canonical color palette for the entire game. Referenced by the global
# Theme resource (game_theme.tres) and by any _draw() code that needs
# consistent branding (CooldownButton, VFX, etc.).

# Backgrounds
const BG_DARK: Color = Color(0.12, 0.14, 0.19)
const PANEL_BG: Color = Color(0.18, 0.21, 0.28)
const PANEL_BORDER: Color = Color(0.28, 0.32, 0.40)

# Accent
const ACCENT_GOLD: Color = Color(0.83, 0.66, 0.20)
const ACCENT_RED: Color = Color(0.80, 0.25, 0.25)
const ACCENT_GREEN: Color = Color(0.30, 0.75, 0.35)
const ACCENT_CYAN: Color = Color(0.20, 0.70, 1.00)

# Text
const TEXT_PRIMARY: Color = Color(0.93, 0.91, 0.87)
const TEXT_SECONDARY: Color = Color(0.62, 0.60, 0.56)

# Buttons
const BTN_NORMAL: Color = Color(0.24, 0.28, 0.36)
const BTN_HOVER: Color = Color(0.30, 0.35, 0.44)
const BTN_PRESSED: Color = Color(0.16, 0.19, 0.25)
const BTN_DISABLED: Color = Color(0.18, 0.20, 0.24)
const BTN_BORDER: Color = Color(0.40, 0.44, 0.52)

# CooldownButton
const COOLDOWN_READY: Color = Color(0.85, 0.4, 0.15)
const COOLDOWN_ACTIVE: Color = Color(0.35, 0.2, 0.1)
const COOLDOWN_BORDER: Color = Color(0.1, 0.05, 0.0)
