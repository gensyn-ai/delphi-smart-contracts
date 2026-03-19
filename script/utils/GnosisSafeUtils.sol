// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Contracts
import {GnosisSafeL2} from "@safe-contracts/GnosisSafeL2.sol";

// Types
import {Enum} from "@safe-contracts/GnosisSafeL2.sol";

// Libraries
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {OwnerManager} from "@safe-contracts/base/OwnerManager.sol";

library GnosisSafeUtils {
    // Types
    struct Sig {
        address addr;
        bytes sig;
    }

    // Libraries
    using Arrays for address[];
    using Strings for uint256;

    // ===== INTERNAL FUNCTIONS =====

    function buildJointSigAndExecTransaction(GnosisSafeL2 safeProxy, address to, bytes memory data, bytes[] memory sigs)
        internal
        returns (bool)
    {
        // TODO delete
        bytes32 txHash = _getTransactionHash(safeProxy, to, data);
        bytes memory jointSig = _checkAndBuildJointSig(safeProxy, txHash, sigs);
        return _execTransaction({safeProxy: safeProxy, to: to, data: data, jointSig: jointSig});
    }

    function generateRemoveOwnerCalldata(GnosisSafeL2 safe, address owner, uint256 newThreshold)
        internal
        view
        returns (bytes memory)
    {
        address prevOwner = _getPrevOwner(safe, owner);
        return abi.encodeCall(OwnerManager.removeOwner, (prevOwner, owner, newThreshold));
    }

    // ===== PRIVATE FUNCTIONS =====

    function _execTransaction(GnosisSafeL2 safeProxy, address to, bytes memory data, bytes memory jointSig)
        private
        returns (bool)
    {
        return safeProxy.execTransaction({
            to: to,
            value: 0,
            data: data,
            operation: Enum.Operation.Call,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(0),
            signatures: jointSig
        });
    }

    function _checkAndBuildJointSig(GnosisSafeL2 safeProxy, bytes32 txHash, bytes[] memory signatures)
        private
        view
        returns (bytes memory jointSig)
    {
        // Initialize arrays
        address[] memory addresses = new address[](signatures.length);
        Sig[] memory sigs = new Sig[](signatures.length);

        // For each signature
        for (uint256 i = 0; i < signatures.length; i++) {
            // Recover address
            address addr = ECDSA.recover(txHash, signatures[i]);

            // Ensure address is a safe owner
            require(safeProxy.isOwner(addr), string.concat("problem on signature ", i.toString()));

            // Store address
            addresses[i] = addr;

            // Store sig
            sigs[i] = Sig({addr: addr, sig: signatures[i]});
        }

        // Sort addresses
        address[] memory sortedAddresses = addresses.sort();

        // Sort signatures (according to sorted addresses)
        bytes[] memory sortedSignatures = new bytes[](sigs.length);
        for (uint256 i = 0; i < sortedAddresses.length; i++) {
            sortedSignatures[i] = _findSignatureByAddr(sigs, sortedAddresses[i]);
        }

        // Build joint signature
        for (uint256 i = 0; i < sortedSignatures.length; i++) {
            jointSig = abi.encodePacked(jointSig, sortedSignatures[i]);
        }
    }

    function _findSignatureByAddr(Sig[] memory sigs, address addr) private pure returns (bytes memory) {
        for (uint256 i = 0; i < sigs.length; i++) {
            if (sigs[i].addr == addr) {
                return sigs[i].sig;
            }
        }
        revert("No signature provided with this address");
    }

    function _getTransactionHash(GnosisSafeL2 safeProxy, address to, bytes memory data)
        internal
        view
        returns (bytes32)
    {
        return safeProxy.getTransactionHash({
            to: to,
            value: 0,
            data: data,
            operation: Enum.Operation.Call,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(0),
            _nonce: safeProxy.nonce()
        });
    }

    function _getPrevOwner(GnosisSafeL2 safe, address owner) private view returns (address) {
        address[] memory owners = safe.getOwners();

        // Gnosis Safe maintains owners as a circular linked list with address(1) as a sentinel.
        // Removing an owner requires passing the owner that precedes it in the list.
        if (owners[0] == owner) {
            return address(1);
        }

        for (uint256 i = 1; i < owners.length; i++) {
            if (owners[i] == owner) {
                return owners[i - 1];
            }
        }

        revert("OWNER NOT VALID");
    }
}
