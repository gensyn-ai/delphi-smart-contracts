// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DynamicParimutuel_Invariants} from "./dpm/DynamicParimutuelInvariants.t.sol";
import {Token_Invariants} from "./token/TokenInvariants.t.sol";

// Other
import {IEndToEndHandler} from "../handlers/IEndToEndHandler.sol";

abstract contract All_Invariants is DynamicParimutuel_Invariants, Token_Invariants {
    struct Error {
        string label;
        bytes4 selector;
    }

    function afterInvariant() external {
        // Initialize total returns
        uint256 totalReturns;

        // Initialize errors array
        Error[] memory errors = new Error[](1);

        // Build errors array
        errors[0] = Error({label: "NoPossibleActions", selector: IEndToEndHandler.NoPossibleActions.selector});
        // errors[1] = Error({label: "TokensOutNotPositive", selector: IDelphi.TokensOutNotPositive.selector});

        // For each error
        for (uint256 i = 0; i < errors.length; i++) {
            // Get error
            Error memory err = errors[i];

            // Get return count
            uint256 errReturnCount = handler.returnCount(err.selector);

            // Log the return count for this model
            emit log_named_uint(string.concat(err.label, " return count:"), errReturnCount);

            // Add to total returns
            totalReturns += errReturnCount;
        }

        // Log total returns across all models
        emit log_named_uint("Total Returns:", totalReturns);
    }
}
