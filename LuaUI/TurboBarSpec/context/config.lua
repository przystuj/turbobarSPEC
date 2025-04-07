WG.TurboBarSpec = WG.TurboBarSpec or {}

if not WG.TurboBarSpec.CONFIG then
    ---@class WidgetConfig
    WG.TurboBarSpec.CONFIG = {
        DEBUG = {
            LOG_LEVEL = "DEBUG"
        },
        PERFORMANCE = {
            UPDATE_FREQUENCY = 15, -- Frames between updates (0.5 seconds at 30fps)
        },
        EVENTS = {
            COMMANDER = {
                LOW_HEALTH_THRESHOLD = 0.5, -- Percentage of health before raising alert
                CRITICAL_HEALTH_THRESHOLD = 0.35, -- Percentage for critical alert
            }
        }
    }
end