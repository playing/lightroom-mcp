local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'

local PhotoLookup = require 'PhotoLookup'
local Log = require 'Log'

local Handler = {}

local function requireString(value, name)
    if type(value) ~= "string" or value == "" then
        error(name .. " is required")
    end
end

local function safeMetadata(photo, kind, key)
    local ok, value = pcall(function()
        if kind == "formatted" then
            return photo:getFormattedMetadata(key)
        end
        return photo:getRawMetadata(key)
    end)
    if ok then return value end
    return nil
end

local function selectedPhotoOthers(selectedPhotos, activePhoto)
    local others = {}
    if type(selectedPhotos) ~= "table" then
        return others
    end
    for _, photo in ipairs(selectedPhotos) do
        if photo ~= activePhoto then
            table.insert(others, photo)
        end
    end
    return others
end

local function restoreSelection(catalog, activePhoto, selectedPhotos, warnings)
    if type(catalog.setSelectedPhotos) ~= "function" or not activePhoto then
        return
    end
    local ok, err = LrTasks.pcall(function()
        catalog:setSelectedPhotos(activePhoto, selectedPhotoOthers(selectedPhotos, activePhoto))
    end)
    if not ok then
        table.insert(warnings, "selection_not_restored: " .. tostring(err))
    end
end

local function captureActiveSources(catalog)
    if type(catalog.getActiveSources) ~= "function" then
        return nil
    end
    local ok, value = pcall(function() return catalog:getActiveSources() end)
    if ok then return value end
    return nil
end

local function selectAllPhotographsSource(catalog, warnings)
    if type(catalog.setActiveSources) ~= "function" or not catalog.kAllPhotos then
        return
    end
    local ok, err = LrTasks.pcall(function()
        catalog:setActiveSources(catalog.kAllPhotos)
    end)
    if not ok then
        table.insert(warnings, "active_source_not_set: " .. tostring(err))
    end
end

local function restoreActiveSources(catalog, activeSources, warnings)
    if type(catalog.setActiveSources) ~= "function" or not activeSources then
        return
    end
    local ok, err = LrTasks.pcall(function()
        catalog:setActiveSources(activeSources)
    end)
    if not ok then
        table.insert(warnings, "active_source_not_restored: " .. tostring(err))
    end
end

local function createCopyWithAvailableApi(catalog, source, copyName, warnings)
    if type(catalog.createVirtualCopies) == "function"
        and type(catalog.setSelectedPhotos) == "function" then
        local previousActive = nil
        local previousSelection = nil
        local previousActiveSources = captureActiveSources(catalog)
        if type(catalog.getTargetPhoto) == "function" then
            local ok, value = LrTasks.pcall(function() return catalog:getTargetPhoto() end)
            if ok then previousActive = value end
        end
        if type(catalog.getTargetPhotos) == "function" then
            local ok, value = LrTasks.pcall(function() return catalog:getTargetPhotos() end)
            if ok then previousSelection = value end
        end

        selectAllPhotographsSource(catalog, warnings)
        catalog:setSelectedPhotos(source, {})
        local ok, copiesOrErr = LrTasks.pcall(function()
            return catalog:createVirtualCopies()
        end)
        restoreSelection(catalog, previousActive, previousSelection, warnings)
        restoreActiveSources(catalog, previousActiveSources, warnings)
        if not ok then
            error(copiesOrErr)
        end
        if type(copiesOrErr) == "table" then
            return copiesOrErr[1]
        end
    end
    if type(source.createVirtualCopy) == "function" then
        return source:createVirtualCopy()
    end
    error("Lightroom SDK virtual copy creation API unavailable")
end

local function setCopyNameIfRequested(catalog, created, copyName, warnings)
    if not copyName or copyName == "" then
        return false
    end
    if safeMetadata(created, "raw", "copyName") == copyName then
        return true
    end
    if type(created.setRawMetadata) ~= "function" then
        table.insert(warnings, "copy_name_not_set: setRawMetadata unavailable")
        return false
    end
    local ok, err = LrTasks.pcall(function()
        catalog:withWriteAccessDo("Set Virtual Copy Name", function()
            created:setRawMetadata("copyName", copyName)
        end)
    end)
    if not ok then
        table.insert(warnings, "copy_name_not_set: " .. tostring(err))
    end
    return ok
end

local function describePhoto(photo)
    return {
        id = tostring(photo.localIdentifier),
        filename = safeMetadata(photo, "formatted", "fileName"),
        path = safeMetadata(photo, "raw", "path"),
        copyName = safeMetadata(photo, "raw", "copyName"),
    }
end

function Handler.createVirtualCopy(args)
    requireString(args.photo_id, "photo_id")
    if args.copy_name ~= nil and type(args.copy_name) ~= "string" then
        error("copy_name must be a string")
    end

    local catalog = LrApplication.activeCatalog()
    local source
    local created
    local copyNameSet = false
    local warnings = {}

    source = PhotoLookup.resolveOne(catalog, args.photo_id)
    if not source then
        error("Photo not found: " .. args.photo_id)
    end

    created = createCopyWithAvailableApi(catalog, source, args.copy_name, warnings)
    if not created then
        error("Virtual copy API returned no photo")
    end

    copyNameSet = setCopyNameIfRequested(catalog, created, args.copy_name, warnings)

    Log.info("Created virtual copy from photo " .. args.photo_id)

    return {
        success = true,
        source = describePhoto(source),
        virtual_copy = describePhoto(created),
        copy_name_requested = args.copy_name,
        copy_name_set = copyNameSet,
        warnings = warnings,
    }
end

return Handler
