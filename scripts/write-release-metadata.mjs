#!/usr/bin/env node
import { mkdir, writeFile } from 'node:fs/promises'
import process from 'node:process'

import packageManifest from '../package.json' with { type: 'json' }

const release = process.env.VITESSE_RELEASE?.trim() || ''
const commitSha = process.env.VITESSE_COMMIT_SHA?.trim() || ''
const deployedAt = process.env.VITESSE_DEPLOYED_AT?.trim() || ''
const expectedRelease = `v${packageManifest.version}`

if (release !== expectedRelease || !/^v\d+\.\d+\.\d+$/.test(release))
  throw new Error(`VITESSE_RELEASE must be exactly ${expectedRelease}`)
if (!/^[0-9a-f]{40}$/.test(commitSha))
  throw new Error('VITESSE_COMMIT_SHA must be a full lowercase Git revision')
if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(deployedAt) || Number.isNaN(Date.parse(deployedAt)))
  throw new Error('VITESSE_DEPLOYED_AT must be a valid UTC timestamp')

const marker = `${JSON.stringify({ release, commitSha, deployedAt }, null, 2)}\n`
const publicDirectory = new URL('../front-end/.output/public/', import.meta.url)
await mkdir(publicDirectory, { recursive: true })
await Promise.all([
  writeFile(new URL('../.vitesse-release-prepared.json', import.meta.url), marker, { mode: 0o600 }),
  writeFile(new URL('release.json', publicDirectory), marker, { mode: 0o644 }),
])

console.log(`Prepared release identity ${release} (${commitSha})`)
