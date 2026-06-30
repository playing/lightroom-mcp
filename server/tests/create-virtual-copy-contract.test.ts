import { describe, expect, it } from '@jest/globals';
import fs from 'node:fs';
import path from 'node:path';
import { TOOL_CONTRACTS } from '../src/tool-contracts.js';

type ObjectProperty = {
  type?: string;
};

describe('create_virtual_copy contract', () => {
  it('exposes a strict Lightroom virtual copy tool', () => {
    const tool = TOOL_CONTRACTS.find((contract) => contract.name === 'create_virtual_copy');

    expect(tool).toBeDefined();
    expect(tool?.luaHandler).toBe('HandlerVirtualCopies.createVirtualCopy');
    expect(tool?.inputSchema.additionalProperties).toBe(false);
    expect(tool?.inputSchema.required).toEqual(['photo_id']);

    const properties = tool?.inputSchema.properties as Record<string, ObjectProperty>;
    expect(properties.photo_id.type).toBe('string');
    expect(properties.copy_name.type).toBe('string');
  });

  it('is listed in the MCPB manifest', () => {
    const manifestPath = path.resolve(process.cwd(), '..', 'mcpb', 'manifest.json');
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8')) as {
      tools: Array<{ name: string; description: string }>;
    };

    const tool = manifest.tools.find((entry) => entry.name === 'create_virtual_copy');
    expect(tool).toBeDefined();
    expect(tool?.description).toContain('virtual copy');
  });

  it('is registered in the Lua dispatch table', () => {
    const pluginPath = path.resolve(
      process.cwd(),
      '..',
      'plugin',
      'LightroomMCP.lrplugin',
      'PluginInfoProvider.lua',
    );
    const source = fs.readFileSync(pluginPath, 'utf8');

    expect(source).toContain("local HandlerVirtualCopies = require 'HandlerVirtualCopies'");
    expect(source).toContain('create_virtual_copy = HandlerVirtualCopies.createVirtualCopy');
  });
});
