local helper = require 'spec_helper'

local function assertErrorContains(fn, expected)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    assert.is_truthy(string.find(tostring(err), expected, 1, true))
end

local function setup(opts)
    opts = opts or {}
    local catalog = helper.fakeCatalog(opts)
    helper.installImport({
        LrApplication = { activeCatalog = function() return catalog end },
        LrTasks = { pcall = pcall },
        LrLogger = helper.defaultLrLogger(),
    })
    package.loaded.HandlerVirtualCopies = nil
    return catalog, require 'HandlerVirtualCopies'
end

describe("HandlerVirtualCopies.createVirtualCopy", function()
    it("errors without photo_id", function()
        local _, Handler = setup({})

        assert.has_error(function()
            Handler.createVirtualCopy({})
        end, "photo_id is required")
    end)

    it("creates a virtual copy through the explicit catalog source API", function()
        local source = helper.fakePhoto({
            id = "100",
            fileName = "DSC0001.ARW",
            path = "C:/photos/DSC0001.ARW",
        })
        local copy = helper.fakePhoto({
            id = "101",
            fileName = "DSC0001.ARW",
            path = "C:/photos/DSC0001.ARW",
            copyName = "AI_MCP_VALIDATION_100",
        })
        local catalog, Handler = setup({ photos = { source } })
        catalog.createVirtualCopy = function(_, photo)
            assert.are.equal(0, catalog.getWriteAccessCount())
            assert.are.same(source, photo)
            return copy
        end

        local r = Handler.createVirtualCopy({
            photo_id = "100",
            copy_name = "AI_MCP_VALIDATION_100",
        })

        assert.is_true(r.success)
        assert.are.equal("100", r.source.id)
        assert.are.equal("101", r.virtual_copy.id)
        assert.are.equal(0, catalog.getWriteAccessCount())
    end)

    it("falls back to a photo-level virtual copy API", function()
        local copy = helper.fakePhoto({
            id = "102",
            fileName = "DSC0002.ARW",
            path = "C:/photos/DSC0002.ARW",
        })
        local source = helper.fakePhoto({
            id = "100",
            fileName = "DSC0002.ARW",
            path = "C:/photos/DSC0002.ARW",
        })
        source.createVirtualCopy = function()
            return copy
        end
        local _, Handler = setup({ photos = { source } })

        local r = Handler.createVirtualCopy({ photo_id = "100" })

        assert.is_true(r.success)
        assert.are.equal("102", r.virtual_copy.id)
    end)

    it("falls back to the verified selected-photo catalog API", function()
        local source = helper.fakePhoto({
            id = "100",
            fileName = "DSC0005.ARW",
            path = "C:/photos/DSC0005.ARW",
        })
        local previousActive = helper.fakePhoto({
            id = "200",
            fileName = "previous.ARW",
            path = "C:/photos/previous.ARW",
        })
        local previousOther = helper.fakePhoto({
            id = "201",
            fileName = "previous-other.ARW",
            path = "C:/photos/previous-other.ARW",
        })
        local copy = helper.fakePhoto({
            id = "105",
            fileName = "DSC0005.ARW",
            path = "C:/photos/DSC0005.ARW",
        })
        local currentActive = previousActive
        local currentSelection = { previousActive, previousOther }
        local activeSources = { "previous-source" }
        local activeSourceCalls = {}
        local catalog, Handler = setup({ photos = { source, previousActive, previousOther } })
        catalog.kAllPhotos = "all-photos"
        catalog.getActiveSources = function()
            return activeSources
        end
        catalog.setActiveSources = function(_, sources)
            table.insert(activeSourceCalls, sources)
            activeSources = sources
            return true
        end
        catalog.getTargetPhoto = function()
            return currentActive
        end
        catalog.getTargetPhotos = function()
            return currentSelection
        end
        catalog.setSelectedPhotos = function(_, activePhoto, otherPhotos)
            currentActive = activePhoto
            currentSelection = { activePhoto }
            for _, photo in ipairs(otherPhotos) do
                table.insert(currentSelection, photo)
            end
        end
        catalog.createVirtualCopies = function(_, copyName)
            assert.is_nil(copyName)
            assert.are.same(source, currentActive)
            return { copy }
        end

        local r = Handler.createVirtualCopy({ photo_id = "100" })

        assert.is_true(r.success)
        assert.are.equal("105", r.virtual_copy.id)
        assert.are.same("all-photos", activeSourceCalls[1])
        assert.are.same({ "previous-source" }, activeSourceCalls[2])
        assert.are.same(previousActive, currentActive)
        assert.are.same({ previousActive, previousOther }, currentSelection)
    end)

    it("does not create when Lightroom selection did not switch to the source", function()
        local source = helper.fakePhoto({
            id = "100",
            fileName = "DSC0007.ARW",
            path = "C:/photos/DSC0007.ARW",
        })
        local selected = helper.fakePhoto({
            id = "200",
            fileName = "selected.ARW",
            path = "C:/photos/selected.ARW",
        })
        local catalog, Handler = setup({ photos = { source, selected } })
        catalog.kAllPhotos = "all-photos"
        catalog.getActiveSources = function()
            return { "previous-source" }
        end
        catalog.setActiveSources = function()
            return true
        end
        catalog.getTargetPhoto = function()
            return selected
        end
        catalog.getTargetPhotos = function()
            return { selected }
        end
        catalog.setSelectedPhotos = function() end
        catalog.createVirtualCopies = function()
            error("createVirtualCopies should not be called")
        end

        assertErrorContains(function()
            Handler.createVirtualCopy({ photo_id = "100" })
        end, "selected_photo_not_changed")
    end)

    for _, scenario in ipairs({ "multiple", "empty", "wrong", "unreadable" }) do
        it("does not create with an unisolated selection: " .. scenario, function()
            local source = helper.fakePhoto({ id = "100", path = "C:/photos/source.ARW" })
            local previous = helper.fakePhoto({ id = "200", path = "C:/photos/previous.ARW" })
            local active = previous
            local selection = { previous }
            local sources = { "previous-source" }
            local catalog, Handler = setup({ photos = { source, previous } })
            catalog.kAllPhotos = "all-photos"
            catalog.getActiveSources = function() return sources end
            catalog.setActiveSources = function(_, value) sources = value return true end
            catalog.getTargetPhoto = function() return active end
            catalog.getTargetPhotos = function()
                if active == source and scenario == "unreadable" then error("read failed") end
                return selection
            end
            catalog.setSelectedPhotos = function(_, value, others)
                active = value
                if value == source then
                    if scenario == "multiple" then selection = { source, previous }
                    elseif scenario == "wrong" then selection = { previous }
                    else selection = {} end
                else
                    selection = { value }
                    for _, photo in ipairs(others) do table.insert(selection, photo) end
                end
            end
            local created = false
            catalog.createVirtualCopies = function() created = true return {} end

            assertErrorContains(function()
                Handler.createVirtualCopy({ photo_id = "100" })
            end, "selected_photo_set_not_isolated")
            assert.is_false(created)
            assert.are.equal(previous, active)
            assert.are.same({ previous }, selection)
            assert.are.same({ "previous-source" }, sources)
        end)
    end

    it("rejects a created photo that does not match the source file", function()
        local source = helper.fakePhoto({
            id = "100",
            fileName = "DSC0006.ARW",
            path = "C:/photos/DSC0006.ARW",
        })
        local wrongCopy = helper.fakePhoto({
            id = "106",
            fileName = "OTHER.ARW",
            path = "C:/photos/OTHER.ARW",
        })
        local catalog, Handler = setup({ photos = { source } })
        catalog.createVirtualCopy = function()
            return wrongCopy
        end

        assertErrorContains(function()
            Handler.createVirtualCopy({ photo_id = "100" })
        end, "Lightroom SDK virtual copy creation API unavailable")
    end)

    it("rejects a created photo that is actually the source photo", function()
        local source = helper.fakePhoto({
            id = "100",
            fileName = "DSC0009.ARW",
            path = "C:/photos/DSC0009.ARW",
        })
        local catalog, Handler = setup({ photos = { source } })
        catalog.createVirtualCopy = function()
            return source
        end

        assertErrorContains(function()
            Handler.createVirtualCopy({ photo_id = "100" })
        end, "Lightroom SDK virtual copy creation API unavailable")
    end)

    it("rejects a created photo when source file identity is unavailable", function()
        local source = helper.fakePhoto({
            id = "100",
            fileName = "DSC0008.ARW",
        })
        local copy = helper.fakePhoto({
            id = "108",
            fileName = "DSC0008.ARW",
        })
        local catalog, Handler = setup({ photos = { source } })
        catalog.createVirtualCopy = function()
            return copy
        end

        assertErrorContains(function()
            Handler.createVirtualCopy({ photo_id = "100" })
        end, "Lightroom SDK virtual copy creation API unavailable")
    end)

    it("errors clearly when Lightroom exposes no virtual copy API", function()
        local source = helper.fakePhoto({
            id = "100",
            fileName = "DSC0003.ARW",
            path = "C:/photos/DSC0003.ARW",
        })
        local _, Handler = setup({ photos = { source } })

        assert.has_error(function()
            Handler.createVirtualCopy({ photo_id = "100" })
        end, "Lightroom SDK virtual copy creation API unavailable")
    end)

    it("attempts to set the optional copy name", function()
        local source = helper.fakePhoto({
            id = "100",
            fileName = "DSC0004.ARW",
            path = "C:/photos/DSC0004.ARW",
        })
        local copy = helper.fakePhoto({
            id = "103",
            fileName = "DSC0004.ARW",
            path = "C:/photos/DSC0004.ARW",
        })
        local catalog, Handler = setup({ photos = { source } })
        local currentActive = nil
        catalog.kAllPhotos = "all-photos"
        catalog.getActiveSources = function()
            return {}
        end
        catalog.setActiveSources = function()
            return true
        end
        catalog.getTargetPhoto = function()
            return currentActive
        end
        catalog.getTargetPhotos = function()
            if currentActive then return { currentActive } end
            return {}
        end
        catalog.setSelectedPhotos = function(_, activePhoto)
            currentActive = activePhoto
        end
        catalog.createVirtualCopies = function(_, copyName)
            assert.are.equal("AI_MCP_VALIDATION_100", copyName)
            return { copy }
        end

        local r = Handler.createVirtualCopy({
            photo_id = "100",
            copy_name = "AI_MCP_VALIDATION_100",
        })

        assert.is_true(r.copy_name_set)
        assert.are.equal("AI_MCP_VALIDATION_100", r.virtual_copy.copyName)
        assert.are.equal("AI_MCP_VALIDATION_100", copy:getRawMetadata("copyName"))
    end)
end)
