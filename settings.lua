data:extend({
    {
        type = "string-setting",
        name = "anchor-point-of-deconstruction-rectangle",
        setting_type = "runtime-global",
        default_value = "floored-centre",
        allowed_values={"floored-centre","upper-left","lower-left","upper-right","lower-right"}
    },
    {
        type = "int-setting",
        minimum_value=0,
        name = "order-delay",
        setting_type = "startup",
        default_value = 0
    }    
})
