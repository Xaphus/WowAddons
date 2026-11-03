WorldLibrary = WorldLibrary or {}

SLASH_BOOKLIBRARY1 = "/books"
SlashCmdList["BOOKLIBRARY"] = function()
    WorldLibrary.ToggleLibrary()
end
