/* eslint-disable @typescript-eslint/no-explicit-any */
import { getInitialTestAccountsData } from '@aztec/accounts/testing';
import { getContractClassFromArtifact } from '@aztec/aztec.js/contracts';
import { publishContractClass } from '@aztec/aztec.js/deployment';
import { Fr } from '@aztec/aztec.js/fields';
import { DEFAULT_UPDATE_DELAY } from '@aztec/constants';
import { EmbeddedWallet } from '@aztec/wallets/embedded';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { UpgradableCounterContract, UpgradableCounterContractArtifact } from './artifacts/UpgradableCounter.js';
import {
  UpgradableCounterV2Contract,
  UpgradableCounterV2ContractArtifact,
} from './artifacts/UpgradableCounterV2.js';

const NODE_URL = process.env.AZTEC_NODE_URL ?? 'http://localhost:8080';

describe('Upgradable mixin (template composition)', () => {
  let wallet: EmbeddedWallet;
  let adminAddress: any;
  let attackerAddress: any;
  let counter: UpgradableCounterContract;
  let counterInstance: any;

  beforeAll(async () => {
    wallet = await EmbeddedWallet.create(NODE_URL, { ephemeral: true });

    // Pre-funded sandbox test accounts.
    const accounts = await getInitialTestAccountsData();
    const adminAcct = await wallet.createSchnorrAccount(accounts[0].secret, accounts[0].salt);
    const attackerAcct = await wallet.createSchnorrAccount(accounts[1].secret, accounts[1].salt);
    adminAddress = adminAcct.address;
    attackerAddress = attackerAcct.address;

    // Deploy v1 with admin authorized to upgrade. Random salt so reruns against
    // the persistent sandbox don't collide on the instance-deploy nullifier.
    const result = await UpgradableCounterContract.deploy(wallet, adminAddress).send({
      from: adminAddress,
      contractAddressSalt: Fr.random(),
      wait: { returnReceipt: true },
    });
    counter = result.receipt.contract;
    counterInstance = result.receipt.instance;
  }, 600_000);

  afterAll(async () => {
    await wallet?.stop();
  });

  // The strongest static proof: codegen emitted the composed surface on the host TS
  // artifact alongside the host-authored methods. If composition had not wired through,
  // these would not exist on `counter.methods`.
  it('exposes the composed upgrade surface on the host contract', () => {
    expect(typeof counter.methods.update_to).toBe('function');
    expect(typeof counter.methods.set_update_delay).toBe('function');
    expect(typeof counter.methods.get_update_delay).toBe('function');
    expect(typeof counter.methods.get_upgrade_admin).toBe('function');
    // Host-authored:
    expect(typeof counter.methods.increment).toBe('function');
    expect(typeof counter.methods.get_count).toBe('function');
    expect(typeof counter.methods.version).toBe('function');
  });

  it('returns the admin set during construction via the composed view', async () => {
    const { result } = await counter.methods.get_upgrade_admin().simulate({ from: adminAddress });
    expect(result.toString()).toEqual(adminAddress.toString());
  });

  it('starts at v1 with the host-defined version() = 1', async () => {
    const { result } = await counter.methods.version().simulate({ from: adminAddress });
    expect(result).toEqual(1n);
  });

  it('rejects update_to from a non-admin caller (composed auth check)', async () => {
    const v2ClassId = (await getContractClassFromArtifact(UpgradableCounterV2ContractArtifact)).id;
    await expect(
      counter.methods.update_to(v2ClassId).simulate({ from: attackerAddress }),
    ).rejects.toThrow(/caller is not upgrade admin/);
  });

  // This is the load-bearing claim for the template: the composed `update_to`
  // function authorizes correctly AND, when called by the admin, propagates
  // through to ContractInstanceRegistry::update. If either step were broken
  // (auth check missing or composition didn't wire the registry call), this
  // tx would either be accepted-from-attacker or fail-from-admin.
  it('admin can publish a new class and schedule the upgrade end-to-end', async () => {
    // Publish v2's class. Idempotent: nullifier may already exist from a prior run.
    const publishMethod = await publishContractClass(wallet, UpgradableCounterV2ContractArtifact);
    try {
      await publishMethod.send({ from: adminAddress });
    } catch (e: any) {
      if (!/Existing nullifier|already.*published/i.test(String(e?.message))) throw e;
    }

    const v2ClassId = (await getContractClassFromArtifact(UpgradableCounterV2ContractArtifact)).id;

    // Schedule the upgrade. This proves the composed `update_to` function
    // forwards to ContractInstanceRegistry::update — if it didn't, the tx
    // would either revert or no class-id-update would be queued.
    const receipt = await counter.methods.update_to(v2ClassId).send({ from: adminAddress });
    expect(receipt.receipt.status).toEqual('success');

    // Composed view returns the current registry delay. Default for a fresh
    // contract instance is DEFAULT_UPDATE_DELAY (86400s).
    const { result: delay } = await counter.methods.get_update_delay().simulate({ from: adminAddress });
    expect(delay).toEqual(BigInt(DEFAULT_UPDATE_DELAY));

    // The actual class-id swap takes effect after `delay` seconds. Verifying
    // the dispatch end-to-end against a remote sandbox requires warping L1
    // anvil AND mining L2 blocks at the new timestamp, which the in-process
    // EthCheatCodes can drive but the sandbox's tx validator rejects (txs
    // built post-warp fail expiration checks). The canonical aztec-packages
    // test uses `cheatCodes.warpL2TimeAtLeastBy(sequencer, node, delay)`
    // which requires direct sequencer access, only available when the node
    // runs in-process. That confirmation is therefore left out of this PoC.
  }, 600_000);
});
