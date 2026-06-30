local helper = require 'spec_helper'

local function setup(opts)
    opts = opts or {}
    local catalog = helper.fakeCatalog(opts)
    helper.installImport({
        LrApplication = { activeCatalog = function() return catalog end },
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

    it("creates a virtual copy through the catalog API", function()
        local source = helper.fakePhoto({
            id = "100",
            fileName = "DSC0001.ARW",
            path = "C:/photos/DSC0001.ARW",
        })
        local copy = helper.fakePhoto({
            id = "101",
            fileName = "DSC0001.ARW",
            path = "C:/photos/DSC0001.ARW",
            copyName = "Copy 1",
        })
        local catalog, Handler = setup({ photos = { source } })
        catalog.createVirtualCopy = function(_, photo)
            assert.are.same(source, photo)
            return copy
        end

        local r = Handler.createVirtualCopy({ photo_id = "100" })

        assert.is_true(r.success)
        assert.are.equal("100", r.source.id)
        assert.are.equal("101", r.virtual_copy.id)
        assert.are.equal(1, catalog.getWriteAccessCount())
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
        catalog.createVirtualCopy = function()
            return copy
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
