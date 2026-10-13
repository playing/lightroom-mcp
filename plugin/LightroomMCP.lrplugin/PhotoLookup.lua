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
-- Preserve the fork's first path match; upstream uses the last match instead.
-- Neither rule establishes unique identity: guarded writes use verified ids.
function PhotoLookup.resolveMany(catalog, photoIds)
    local results = {}
    local wantedLocalIds = {}
    local wantedPaths = {}
    local remainingPaths = 0
    local remainingIds = 0

    for i, id in ipairs(photoIds) do
        results[i] = { id = id, photo = nil }
        if looksLikePath(id) then
            local key = tostring(id)
            if wantedPaths[key] == nil then wantedPaths[key] = {} end
            table.insert(wantedPaths[key], i)
            remainingPaths = remainingPaths + 1
        else
            local key = tostring(id)
            if wantedLocalIds[key] == nil then wantedLocalIds[key] = {} end
            table.insert(wantedLocalIds[key], i)
            remainingIds = remainingIds + 1
        end
    end

    -- LrCatalog has no findPhotoByLocalIdentifier, so resolution needs one
    -- catalog pass. Path metadata remains untouched for numeric-only batches.
    if remainingIds + remainingPaths == 0 then return results end
    for _, p in ipairs(catalog:getAllPhotos()) do
        local lid = p.localIdentifier
        if lid ~= nil then
            local indexes = wantedLocalIds[tostring(lid)]
            if indexes then
                for _, idx in ipairs(indexes) do
                    results[idx].photo = p
                    remainingIds = remainingIds - 1
                end
                wantedLocalIds[tostring(lid)] = nil
            end
        end
        if remainingPaths > 0 then
            local photoPath = p:getRawMetadata('path')
            local indexes = wantedPaths[photoPath]
            if indexes then
                for _, idx in ipairs(indexes) do
                    results[idx].photo = p
                    remainingPaths = remainingPaths - 1
                end
                wantedPaths[photoPath] = nil
            end
        end
        -- Adopt upstream's early stop without changing the fork's path contract.
        if remainingIds + remainingPaths == 0 then break end
    end

    return results
end

function PhotoLookup.resolveOne(catalog, photoId)
    return PhotoLookup.resolveMany(catalog, { photoId })[1].photo
end

return PhotoLookup
