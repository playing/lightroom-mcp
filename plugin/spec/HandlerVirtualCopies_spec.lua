local helper = require 'spec_helper'

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

    it("creates a virtual copy through the documented selected-photo catalog API", function()
        local source = helper.fakePhoto({
            id = "100",
            fileName = "DSC0001.ARW",
            path = "C:/photos/DSC0001.ARW",
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
            id = "101",
            fileName = "DSC0001.ARW",
            path = "C:/photos/DSC0001.ARW",
            copyName = "AI_MCP_VALIDATION_100",
        })
        local selectionCalls = {}
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
            return previousActive
        end
        catalog.getTargetPhotos = function()
            return { previousActive, previousOther }
        end
        catalog.setSelectedPhotos = function(_, activePhoto, otherPhotos)
            table.insert(selectionCalls, { active = activePhoto, others = otherPhotos })
        end
        catalog.createVirtualCopy = function()
            error("Assertion failed: packed")
        end
        catalog.createVirtualCopies = function(_, copyName)
            assert.is_nil(copyName)
            assert.are.equal(0, catalog.getWriteAccessCount())
            assert.are.same(source, selectionCalls[1].active)
            assert.are.same({}, selectionCalls[1].others)
            return { copy }
        end

        local r = Handler.createVirtualCopy({
            photo_id = "100",
            copy_name = "AI_MCP_VALIDATION_100",
        })

        assert.is_true(r.success)
        assert.are.equal("100", r.source.id)
        assert.are.equal("101", r.virtual_copy.id)
        assert.are.equal(0, catalog.getWriteAccessCount())
        assert.are.same("all-photos", activeSourceCalls[1])
        assert.are.same({ "previous-source" }, activeSourceCalls[2])
        assert.are.same(previousActive, selectionCalls[2].active)
        assert.are.same({ previousOther }, selectionCalls[2].others)
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
        catalog.setSelectedPhotos = function() end
        catalog.createVirtualCopies = function(_, copyName)
            assert.is_nil(copyName)
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
