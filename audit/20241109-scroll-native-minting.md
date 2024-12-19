# [NM-0217] Scroll Native Minting Request

**File(s)**: [L1ScrollReceiverETHUpgradeable.sol](https://github.com/etherfi-protocol/weETH-cross-chain/blob/aa5fd7687686c67febe7f07c3f68da798ef3fd41/contracts/NativeMinting/ReceiverContracts/L1ScrollReceiverETHUpgradeable.sol), [L2OPStackSyncPoolETHUpgradeable.sol](https://github.com/etherfi-protocol/weETH-cross-chain/blob/8467b3903c71790c08f183bcbe8224bfb1c6b0b2/contracts/NativeMinting/L2SyncPoolContracts/L2OPStackSyncPoolETHUpgradeable.sol), [L2ScrollSyncPoolETHUpgradeable](https://github.com/etherfi-protocol/weETH-cross-chain/blob/b953a0260deef2f70ba556ff064d45b21d9bc894/contracts/NativeMinting/L2SyncPoolContracts/L2ScrollSyncPoolETHUpgradeable.sol#L108)

### Summary

This PR extends the cross chain functionality that allows users to natively mint weETH without the need to swap through a DEX by adding support for the Scroll blockchain. In order to add this feature, the smart contracts required slight customizations of the already existing code to integrate with Scroll.

---

### Review conclusions

After reviewing the updated code, we don't see any clear risk on the changes that were implemented. The code seems to work as expected.

---
