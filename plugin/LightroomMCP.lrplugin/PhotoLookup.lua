local PhotoLookup = {}

local function looksLikePath(value)
    local s = tostring(value)
    return string.find(s, "[:/\\]") ~= nil
end

-- Resolve a list of photo identifiers to photo objects.
-- Each id may be a numeric local identifier (string or number) or a file path.
-- Only touches the expensive path metadata when an unresolved identifier
-- looks like a file path. Returns a parallel array:
--   results[i] = { id = inputId, photo = photoOrNil }
function PhotoLookup.resolveMany(catalog, photoIds)
    local results = {}
    local wantedLocalIds = {}
    local candidatePathIndexes = {}

    for i, id in ipairs(photoIds) do
        results[i] = { id = id, photo = nil }
        if looksLikePath(id) then
            table.insert(candidatePathIndexes, i)
        else
            local key = tostring(id)
            if wantedLocalIds[key] == nil then wantedLocalIds[key] = {} end
            table.insert(wantedLocalIds[key], i)
        end
    end

    -- LrCatalog has no findPhotoByLocalIdentifier, so local-id lookup still
    -- needs one catalog pass. Keep this pass cheap by avoiding getRawMetadata.
    for _, p in ipairs(catalog:getAllPhotos()) do
        local lid = p.localIdentifier
        if lid ~= nil then
            local indexes = wantedLocalIds[tostring(lid)]
            if indexes then
                for _, idx in ipairs(indexes) do
                    results[idx].photo = p
                end
            end
        end
    end

    if #candidatePathIndexes > 0 then
        local wantedPaths = {}
        local remaining = 0
        for _, idx in ipairs(candidatePathIndexes) do
            if results[idx].photo == nil then
                local key = tostring(results[idx].id)
                if wantedPaths[key] == nil then wantedPaths[key] = {} end
                table.insert(wantedPaths[key], idx)
                remaining = remaining + 1
            end
        end

        if remaining > 0 then
            for _, p in ipairs(catalog:getAllPhotos()) do
                local photoPath = p:getRawMetadata('path')
                local indexes = wantedPaths[photoPath]
                if indexes then
                    for _, idx in ipairs(indexes) do
                        results[idx].photo = p
                        remaining = remaining - 1
                    end
                    wantedPaths[photoPath] = nil
                    if remaining <= 0 then break end
                end
            end
        end
    end

    return results
end

function PhotoLookup.resolveOne(catalog, photoId)
    return PhotoLookup.resolveMany(catalog, { photoId })[1].photo
end

return PhotoLookup
