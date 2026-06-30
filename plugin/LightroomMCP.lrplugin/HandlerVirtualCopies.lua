local LrApplication = import 'LrApplication'

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

local function createCopyWithAvailableApi(catalog, source)
    if type(catalog.createVirtualCopy) == "function" then
        return catalog:createVirtualCopy(source)
    end
    if type(source.createVirtualCopy) == "function" then
        return source:createVirtualCopy()
    end
    if type(catalog.createVirtualCopies) == "function" then
        local copies = catalog:createVirtualCopies({ source })
        if type(copies) == "table" then
            return copies[1]
        end
    end
    error("Lightroom SDK virtual copy creation API unavailable")
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

    catalog:withWriteAccessDo("Create Virtual Copy", function()
        source = PhotoLookup.resolveOne(catalog, args.photo_id)
        if not source then
            error("Photo not found: " .. args.photo_id)
        end

        created = createCopyWithAvailableApi(catalog, source)
        if not created then
            error("Virtual copy API returned no photo")
        end

        if args.copy_name and args.copy_name ~= "" then
            if type(created.setRawMetadata) == "function" then
                local ok, err = pcall(function()
                    created:setRawMetadata("copyName", args.copy_name)
                end)
                copyNameSet = ok
                if not ok then
                    table.insert(warnings, "copy_name_not_set: " .. tostring(err))
                end
            else
                table.insert(warnings, "copy_name_not_set: setRawMetadata unavailable")
            end
        end
    end)

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
