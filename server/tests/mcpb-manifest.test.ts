import { describe, expect, it } from '@jest/globals';
import fs from 'node:fs';
import path from 'node:path';
import { TOOL_CONTRACTS } from '../src/tool-contracts.js';

type McpbManifest = {
  tools: Array<{ name: string; description: string }>;
};

function readManifest(): McpbManifest {
  const manifestPath = path.resolve(process.cwd(), '..', 'mcpb', 'manifest.json');
  return JSON.parse(fs.readFileSync(manifestPath, 'utf8')) as McpbManifest;
}

describe('mcpb manifest', () => {
  it('lists exactly the public MCP tool contracts in order', () => {
    const manifest = readManifest();
    expect(manifest.tools.map((tool) => tool.name)).toEqual(
      TOOL_CONTRACTS.map((contract) => contract.name),
    );
  });

  it('describes every bundled tool', () => {
    const manifest = readManifest();
    for (const tool of manifest.tools) {
      expect(tool.description.trim().length).toBeGreaterThan(10);
    }
  });
});
