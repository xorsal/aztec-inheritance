/* eslint-disable @typescript-eslint/no-explicit-any */
import { getInitialTestAccountsData } from '@aztec/accounts/testing';
import { getContractClassFromArtifact } from '@aztec/aztec.js/contracts';
import { publishContractClass } from '@aztec/aztec.js/deployment';
import { Fr } from '@aztec/aztec.js/fields';
import { DEFAULT_UPDATE_DELAY } from '@aztec/constants';
import { EmbeddedWallet } from '@aztec/wallets/embedded';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { OwnableUpgradableCounterContract } from './artifacts/OwnableUpgradableCounter.js';
import { OwnableUpgradableCounterV2ContractArtifact } from './artifacts/OwnableUpgradableCounterV2.js';

const NODE_URL = process.env.AZTEC_NODE_URL ?? 'http://localhost:8080';

describe('OwnableUpgradableCounter (composed ownable + upgradable)', () => {
  let wallet: EmbeddedWallet;
  let ownerAddress: any;
  let newOwnerAddress: any;
  let attackerAddress: any;
  let counter: OwnableUpgradableCounterContract;

  beforeAll(async () => {
    wallet = await EmbeddedWallet.create(NODE_URL, { ephemeral: true });

    const accounts = await getInitialTestAccountsData();
    const ownerAcct = await wallet.createSchnorrAccount(accounts[0].secret, accounts[0].salt);
    const attackerAcct = await wallet.createSchnorrAccount(accounts[1].secret, accounts[1].salt);
    const newOwnerAcct = await wallet.createSchnorrAccount(accounts[2].secret, accounts[2].salt);
    ownerAddress = ownerAcct.address;
    attackerAddress = attackerAcct.address;
    newOwnerAddress = newOwnerAcct.address;

    const { contract } = await OwnableUpgradableCounterContract.deploy(wallet, ownerAddress).send({
      from: ownerAddress,
      contractAddressSalt: Fr.random(),
    });
    counter = contract;
  }, 600_000);

  afterAll(async () => {
    await wallet?.stop();
  });

  // Strongest static proof of composition: the codegen'd TS artifact exposes BOTH
  // template surfaces as native methods alongside the host-authored functions.
  it('exposes both composed surfaces (ownable + upgradable) on the host contract', () => {
    // Ownable composed
    expect(typeof counter.methods.get_owner).toBe('function');
    expect(typeof counter.methods.transfer_ownership).toBe('function');
    // Upgradable composed
    expect(typeof counter.methods.update_to).toBe('function');
    expect(typeof counter.methods.set_update_delay).toBe('function');
    expect(typeof counter.methods.get_update_delay).toBe('function');
    // Host-authored
    expect(typeof counter.methods.increment).toBe('function');
    expect(typeof counter.methods.set_count).toBe('function');
    expect(typeof counter.methods.get_count).toBe('function');
    expect(typeof counter.methods.version).toBe('function');
  });

  it('returns the owner set during construction via the ownable view', async () => {
    const { result } = await counter.methods.get_owner().simulate({ from: ownerAddress });
    expect(result.toString()).toEqual(ownerAddress.toString());
  });

  it('starts at v1 with host-defined version() = 1', async () => {
    const { result } = await counter.methods.version().simulate({ from: ownerAddress });
    expect(result).toEqual(1n);
  });

  it('rejects #[only_owner] set_count from a non-owner caller', async () => {
    await expect(
      counter.methods.set_count(42n).simulate({ from: attackerAddress }),
    ).rejects.toThrow(/caller is not owner/);
  });

  it('rejects update_to from a non-owner caller (upgradable auth)', async () => {
    const v2ClassId = (await getContractClassFromArtifact(OwnableUpgradableCounterV2ContractArtifact)).id;
    await expect(
      counter.methods.update_to(v2ClassId).simulate({ from: attackerAddress }),
    ).rejects.toThrow(/caller is not owner/);
  });

  it('rejects transfer_ownership to the zero address', async () => {
    const zero = ownerAddress.constructor.ZERO ?? Fr.ZERO;
    await expect(
      counter.methods.transfer_ownership(zero).simulate({ from: ownerAddress }),
    ).rejects.toThrow(/new owner is zero/);
  });

  // Load-bearing combined test: rotate ownership, then prove only the new
  // owner can drive update_to. This exercises BOTH templates together against
  // the shared `owner` storage slot.
  it('rotates ownership, then the new owner can schedule an upgrade end-to-end', async () => {
    // Old owner transfers to the new owner.
    await counter.methods.transfer_ownership(newOwnerAddress).send({ from: ownerAddress });
    const { result: postTransfer } = await counter.methods.get_owner().simulate({ from: newOwnerAddress });
    expect(postTransfer.toString()).toEqual(newOwnerAddress.toString());

    // Old owner is no longer authorized.
    await expect(
      counter.methods.set_count(1n).simulate({ from: ownerAddress }),
    ).rejects.toThrow(/caller is not owner/);

    // Publish v2's class. Idempotent against existing-nullifier on rerun.
    const publishMethod = await publishContractClass(wallet, OwnableUpgradableCounterV2ContractArtifact);
    try {
      await publishMethod.send({ from: newOwnerAddress });
    } catch (e: any) {
      if (!/Existing nullifier|already.*published/i.test(String(e?.message))) throw e;
    }

    const v2ClassId = (await getContractClassFromArtifact(OwnableUpgradableCounterV2ContractArtifact)).id;

    // New owner schedules the upgrade. If the shared-owner-slot wiring were
    // wrong, this would either fail auth (because update_to's check reads
    // the same slot transfer_ownership wrote) or fail on the registry call.
    const receipt = await counter.methods.update_to(v2ClassId).send({ from: newOwnerAddress });
    expect(receipt.receipt.status).toEqual('success');

    // Confirm the composed update-delay view still works for the new owner.
    const { result: delay } = await counter.methods.get_update_delay().simulate({ from: newOwnerAddress });
    expect(delay).toEqual(BigInt(DEFAULT_UPDATE_DELAY));
  }, 600_000);
});
