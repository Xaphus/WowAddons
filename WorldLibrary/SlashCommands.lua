WorldLibrary = WorldLibrary or {}

SLASH_BOOKLIBRARY1 = "/books"
SlashCmdList["BOOKLIBRARY"] = function()
    local ui = WorldLibrary.BuildBookLibraryUI()
    if ui then
        if ui:IsShown() then
            ui:Hide()
        else
            ui:RefreshList()
            ui:Show()
        end
    end
end
