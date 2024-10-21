data:extend({
    {
        type = "bool-setting",
        name = "factoriomaps-periodic-save-enable",
        setting_type = "runtime-global",
        default_value = true,
    },
    {
        type = "double-setting",
        name = "factoriomaps-periodic-save-frequency",
        setting_type = "runtime-global",
        default_value = 2.5,
		minimum_value = 1 / 60,
    },
    {
        type = "string-setting",
        name = "factoriomaps-periodic-save-name",
        setting_type = "runtime-global",
        default_value = "%SEED%-%TICK%",
		allow_blank = true,
    },
    {
        type = "bool-setting",
        name = "factoriomaps-show-startup-guide",
        setting_type = "runtime-global",
        default_value = true,
    },
})