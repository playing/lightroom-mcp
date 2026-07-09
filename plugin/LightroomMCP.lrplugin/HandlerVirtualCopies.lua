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

local function photoId(photo)
    local ok, value = pcall(function() return photo.localIdentifier end)
    if ok and value ~= nil then
        return tostring(value)
    end
    return nil
end

local function sameSourceFile(source, created)
    local sourcePath = safeMetadata(source, "raw", "path")
    local createdPath = safeMetadata(created, "raw", "path")
    return sourcePath ~= nil and createdPath ~= nil and sourcePath == createdPath
end

local function samePhoto(a, b)
    if a == b then
        return true
    end
    local aId = photoId(a)
    local bId = photoId(b)
    return aId ~= nil and bId ~= nil and aId == bId
end

local function selectedPhotoOthers(selectedPhotos, activePhoto)
    local others = {}
    if type(selectedPhotos) ~= "table" then
        return others
    end
    for _, photo in ipairs(selectedPhotos) do
        if not samePhoto(photo, activePhoto) then
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
    local ok, value = LrTasks.pcall(function() return catalog:getActiveSources() end)
    if ok then return value end
    return nil
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

local function selectAllPhotographsSource(catalog, warnings)
    if type(catalog.setActiveSources) ~= "function" or not catalog.kAllPhotos then
        table.insert(warnings, "active_source_not_set: setActiveSources unavailable")
        return false
    end
    local ok, result = LrTasks.pcall(function()
        return catalog:setActiveSources(catalog.kAllPhotos)
    end)
    if not ok then
        table.insert(warnings, "active_source_not_set: " .. tostring(result))
        return false
    end
    if result == false then
        table.insert(warnings, "active_source_not_set: Lightroom returned false")
        return false
    end
    return true
end

local function getTargetPhoto(catalog, warnings, label)
    if type(catalog.getTargetPhoto) ~= "function" then
        table.insert(warnings, label .. "_unavailable")
        return nil
    end
    local ok, value = LrTasks.pcall(function() return catalog:getTargetPhoto() end)
    if ok then return value end
    table.insert(warnings, label .. "_failed: " .. tostring(value))
    return nil
end

local function validCreatedPhoto(source, candidate, warnings, label)
    if samePhoto(source, candidate) then
        table.insert(warnings, label .. "_returned_source_photo")
        return nil
    end
    if photoId(candidate) and sameSourceFile(source, candidate) then
        return candidate
    end
    table.insert(warnings, label .. "_returned_non_matching_photo")
    return nil
end

local function tryCreate(warnings, label, fn)
    local ok, result = LrTasks.pcall(fn)
    if ok then
        return result
    end
    table.insert(warnings, label .. "_failed: " .. tostring(result))
    return nil
end

local function createCopyFromVerifiedSelection(catalog, source, copyName, warnings)
    if type(catalog.createVirtualCopies) ~= "function"
        or type(catalog.setSelectedPhotos) ~= "function" then
        return nil
    end

    local previousActive = getTargetPhoto(catalog, warnings, "previous_target_photo")
    local previousSelection = nil
    local previousActiveSources = captureActiveSources(catalog)
    if type(catalog.getTargetPhotos) == "function" then
        local ok, value = LrTasks.pcall(function() return catalog:getTargetPhotos() end)
        if ok then
            previousSelection = value
        else
            table.insert(warnings, "previous_target_photos_failed: " .. tostring(value))
        end
    end

    local sourceReady = selectAllPhotographsSource(catalog, warnings)
    local selected = false
    if sourceReady then
        local ok, err = LrTasks.pcall(function()
            catalog:setSelectedPhotos(source, {})
        end)
        if ok then
            selected = true
            if type(LrTasks.sleep) == "function" then
                LrTasks.sleep(0.2)
            end
        else
            table.insert(warnings, "source_selection_failed: " .. tostring(err))
        end
    end

    local selectedSource = nil
    if selected then
        selectedSource = getTargetPhoto(catalog, warnings, "selected_target_photo")
    end
    if not samePhoto(source, selectedSource) then
        table.insert(warnings, "selected_photo_not_changed: expected "
            .. tostring(photoId(source)) .. " got " .. tostring(photoId(selectedSource)))
        restoreSelection(catalog, previousActive, previousSelection, warnings)
        restoreActiveSources(catalog, previousActiveSources, warnings)
        return nil
    end

    local copies = tryCreate(warnings, "selected_create_virtual_copies", function()
        return catalog:createVirtualCopies(copyName)
    end)
    restoreSelection(catalog, previousActive, previousSelection, warnings)
    restoreActiveSources(catalog, previousActiveSources, warnings)

    if type(copies) ~= "table" then
        table.insert(warnings, "selected_create_virtual_copies_returned_non_table")
        return nil
    end
    return validCreatedPhoto(source, copies[1], warnings, "selected_create_virtual_copies")
end

local function unavailableError(warnings)
    if #warnings > 0 then
        error("Lightroom SDK virtual copy creation API unavailable: " .. table.concat(warnings, " | "))
    end
    error("Lightroom SDK virtual copy creation API unavailable")
end

local function createCopyWithAvailableApi(catalog, source, copyName, warnings)
    if type(catalog.createVirtualCopy) == "function" then
        local created = tryCreate(warnings, "catalog_create_virtual_copy", function()
            return catalog:createVirtualCopy(source)
        end)
        if created then
            local valid = validCreatedPhoto(source, created, warnings, "catalog_create_virtual_copy")
            if valid then return valid end
        end
    end
    if type(source.createVirtualCopy) == "function" then
        local created = tryCreate(warnings, "source_create_virtual_copy", function()
            return source:createVirtualCopy()
        end)
        if created then
            local valid = validCreatedPhoto(source, created, warnings, "source_create_virtual_copy")
            if valid then return valid end
        end
    end
    local selectedCopy = createCopyFromVerifiedSelection(catalog, source, copyName, warnings)
    if selectedCopy then
        return selectedCopy
    end
    unavailableError(warnings)
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
